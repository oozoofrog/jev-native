import AppKit
import MetalKit
import simd

enum MetalTopologyID: Hashable { case cycle(Int),record(Int) }
struct MetalTopologyCard {
    let id:MetalTopologyID
    let frame:CGRect
    let title:String
    let badge:String
    let text:String
    let footnote:String
    var selected = false
    var current = false
    var isRail = false
    var accessibilityLabel:String { title+" · "+badge+" · "+text+" · "+footnote }
}

private final class MetalTopologyAX:NSAccessibilityElement {
    var press:(() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        guard let press else { return false }
        DispatchQueue.main.async(execute:press); return true
    }
}

/// All graph surfaces, connections, moving marks and glyph textures are composited by Metal.
/// AppKit shapes Korean/Unicode glyphs and supplies selectable full-text inspection separately.
@MainActor final class MetalTopologyView:MTKView,MTKViewDelegate {
    private struct Vertex { var position:SIMD2<Float>; var uv:SIMD2<Float>; var color:SIMD4<Float> }
    private struct Uniforms { var viewport:SIMD4<Float>; var transform:SIMD4<Float> }
    private let commands:MTLCommandQueue?
    private var solidPipeline:MTLRenderPipelineState?
    private var textPipeline:MTLRenderPipelineState?
    private var textures:[String:MTLTexture] = [:]
    private var accessibilityNodes:[MetalTopologyID:MetalTopologyAX] = [:]
    private var dragPoint:CGPoint?
    private var pendingClick:MetalTopologyID?
    private var dragged = false
    private(set) var rendererFailure:String?
    private(set) var submittedFrames = 0
    private(set) var completedFrames = 0
    private(set) var lastGPUError:String?
    var cards:[MetalTopologyCard] = [] { didSet { refreshAccessibility() } }
    var camera = TopologyCamera()
    var railOffset:CGFloat = 0
    var mainViewport:CGRect { CGRect(x:railWidth+24,y:16,width:max(1,bounds.width-railWidth-40),height:max(1,bounds.height-32)) }
    var railWidth:CGFloat { bounds.width >= 650 ? 178 : 142 }
    var eventTime:Double = 0
    var pulseStart:Double?
    var onSelect:(MetalTopologyID) -> Void = { _ in }
    var onManual:() -> Void = {}
    private var dark:Bool { effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    init() {
        let gpu = MTLCreateSystemDefaultDevice(); commands = gpu?.makeCommandQueue()
        super.init(frame:.zero,device:gpu)
        colorPixelFormat = .bgra8Unorm; framebufferOnly = true
        isPaused = true; enableSetNeedsDisplay = false; autoResizeDrawable = true; delegate = self
        setAccessibilityElement(false)
        do {
            guard let gpu,commands != nil else { throw Failure("Metal device or command queue unavailable") }
            let library = try gpu.makeLibrary(source:Self.shader,options:nil)
            func pipeline(_ fragment:String) throws -> MTLRenderPipelineState {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name:"topologyVertex")
                descriptor.fragmentFunction = library.makeFunction(name:fragment)
                let color = descriptor.colorAttachments[0]!
                color.pixelFormat = colorPixelFormat; color.isBlendingEnabled = true
                color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try gpu.makeRenderPipelineState(descriptor:descriptor)
            }
            solidPipeline = try pipeline("topologySolid"); textPipeline = try pipeline("topologyText")
        } catch { rendererFailure = String(describing:error) }
    }
    required init(coder:NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); textures = [:]; draw() }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) { updateAXFrames() }
    func draw(in view:MTKView) {
        guard rendererFailure == nil,let pass = currentRenderPassDescriptor,let drawable = currentDrawable,
              let buffer = commands?.makeCommandBuffer() else { return }
        encode(pass:pass,buffer:buffer,renderSize:drawableSize)
        buffer.present(drawable); submittedFrames += 1
        buffer.addCompletedHandler { [weak self] completed in
            let error = completed.error.map { String(describing:$0) }
            Task { @MainActor [weak self] in self?.completedFrames += 1; self?.lastGPUError = error }
        }
        buffer.commit(); updateAXFrames()
    }
    private func rgba(_ color:NSColor) -> SIMD4<Float> {
        let c = color.usingColorSpace(.deviceRGB) ?? .black
        return SIMD4(Float(c.redComponent*c.alphaComponent),Float(c.greenComponent*c.alphaComponent),Float(c.blueComponent*c.alphaComponent),Float(c.alphaComponent))
    }
    private func encode(pass:MTLRenderPassDescriptor,buffer:MTLCommandBuffer,renderSize:CGSize) {
        let background = dark ? NSColor(calibratedWhite:0.105,alpha:1) : NSColor(calibratedWhite:0.96,alpha:1)
        let bg = rgba(background)
        pass.colorAttachments[0].clearColor = MTLClearColor(red:Double(bg.x),green:Double(bg.y),blue:Double(bg.z),alpha:1)
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor:pass),let solidPipeline,let textPipeline else { return }
        encoder.label = "JEV topology: GPU cards, edges and glyphs"
        let main = mainViewport
        let offset = SIMD4<Float>(Float(main.midX-camera.center.x*camera.scale),Float(main.midY-camera.center.y*camera.scale),Float(camera.scale),0)
        var uniforms = Uniforms(viewport:SIMD4(Float(bounds.width),Float(bounds.height),0,0),transform:offset)
        func setSpace(rail:Bool) { uniforms.transform = rail ? SIMD4(0,0,1,0) : offset; encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1) }
        func draw(_ vertices:[Vertex],text:MTLTexture? = nil) {
            guard !vertices.isEmpty,let gpu = device,let vertexBuffer = gpu.makeBuffer(bytes:vertices,length:MemoryLayout<Vertex>.stride*vertices.count,options:.storageModeShared) else { return }
            encoder.setRenderPipelineState(text == nil ? solidPipeline : textPipeline)
            encoder.setVertexBuffer(vertexBuffer,offset:0,index:0)
            if let text { encoder.setFragmentTexture(text,index:0) }
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:vertices.count)
        }
        func scissor(_ rect:CGRect) {
            let sx = renderSize.width/max(1,bounds.width),sy = renderSize.height/max(1,bounds.height)
            encoder.setScissorRect(MTLScissorRect(x:max(0,Int(rect.minX*sx)),y:max(0,Int(rect.minY*sy)),width:max(1,Int(rect.width*sx)),height:max(1,Int(rect.height*sy))))
        }
        scissor(main); setSpace(rail:false)
        let corner = camera.world(main.origin,in:main)
        let far = camera.world(CGPoint(x:main.maxX,y:main.maxY),in:main)
        var dots:[Vertex] = []
        let dotColor = rgba(NSColor.separatorColor.withAlphaComponent(0.4))
        for y in stride(from:floor(corner.y/24)*24,through:far.y,by:24) {
            for x in stride(from:floor(corner.x/24)*24,through:far.x,by:24) { dots += Self.quad(CGRect(x:x,y:y,width:1,height:1),color:dotColor) }
        }
        draw(dots)
        let stages = cards.filter { !$0.isRail }
        for (a,b) in zip(stages,stages.dropFirst()) {
            let points = Self.connection(a.frame,b.frame)
            var vertices:[Vertex] = []
            for (first,last) in zip(points,points.dropFirst()) { vertices += Self.line(first,last,width:1.4,color:rgba(.separatorColor)) }
            if let end = points.last,points.count > 1 {
                let prev = points[points.count-2],angle = atan2(end.y-prev.y,end.x-prev.x)
                let l = CGPoint(x:end.x-8*cos(angle-0.5),y:end.y-8*sin(angle-0.5)),r = CGPoint(x:end.x-8*cos(angle+0.5),y:end.y-8*sin(angle+0.5))
                vertices += Self.triangle(end,l,r,color:rgba(.secondaryLabelColor))
            }
            draw(vertices)
            if b.current,let start = pulseStart,eventTime-start < 1.1 {
                let position = Self.pathPoint(points,progress:max(0,min(1,(eventTime-start)/1.1)))
                draw(Self.rounded(CGRect(x:position.x-3,y:position.y-3,width:6,height:6),radius:3,color:rgba(.systemIndigo)))
            }
        }
        for card in stages where camera.screen(card.frame,in:main).intersects(main) { render(card) }
        scissor(CGRect(x:0,y:0,width:railWidth+16,height:bounds.height)); setSpace(rail:true)
        let railCards = cards.filter(\.isRail)
        for (a,b) in zip(railCards,railCards.dropFirst()) { draw(Self.line(CGPoint(x:a.frame.midX,y:a.frame.maxY),CGPoint(x:b.frame.midX,y:b.frame.minY),width:1,color:rgba(.separatorColor))) }
        for card in railCards where card.frame.intersects(bounds) { render(card) }
        encoder.endEncoding()

        func render(_ card:MetalTopologyCard) {
            let surface = dark ? NSColor(calibratedWhite:0.16,alpha:1) : .controlBackgroundColor
            let outline:NSColor = card.current ? .systemIndigo : card.selected ? .labelColor : .separatorColor
            draw(Self.rounded(card.frame,radius:9,color:rgba(outline)))
            let border:CGFloat = card.current || card.selected ? 1.5 : 1
            draw(Self.rounded(card.frame.insetBy(dx:border,dy:border),radius:8,color:rgba(surface)))
            if let texture = textTexture(card) { draw(Self.quad(card.frame,color:SIMD4(repeating:1)),text:texture) }
        }
    }
    private func textTexture(_ card:MetalTopologyCard) -> MTLTexture? {
        let key = "\(dark)|\(card.frame.width)|\(card.frame.height)|\(card.title)|\(card.badge)|\(card.text)|\(card.footnote)"
        if let cached = textures[key] { return cached }
        guard let device else { return nil }
        let scale:CGFloat = max(2,window?.backingScaleFactor ?? 2),width = Int(ceil(card.frame.width*scale)),height = Int(ceil(card.frame.height*scale))
        guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),let data = context.data else { return nil }
        context.scaleBy(x:scale,y:scale); context.translateBy(x:0,y:card.frame.height); context.scaleBy(x:1,y:-1)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            func text(_ value:String,_ rect:CGRect,_ size:CGFloat,_ weight:NSFont.Weight = .regular,_ secondary:Bool = false) {
                let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail; p.lineSpacing = 3
                let attributes:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:secondary ? NSColor.secondaryLabelColor : .labelColor,.paragraphStyle:p]
                (value as NSString).draw(with:rect,options:[.usesLineFragmentOrigin,.truncatesLastVisibleLine],attributes:attributes)
            }
            text(card.title,CGRect(x:13,y:12,width:card.frame.width-26,height:22),14,.semibold)
            text(card.badge,CGRect(x:13,y:35,width:card.frame.width-26,height:18),11,.medium,true)
            if card.isRail { text(card.footnote,CGRect(x:13,y:card.frame.height-29,width:card.frame.width-26,height:18),11,.regular,true) }
            else {
                text(card.text,CGRect(x:13,y:61,width:card.frame.width-26,height:card.frame.height-95),14)
                text(card.footnote,CGRect(x:13,y:card.frame.height-27,width:card.frame.width-26,height:18),11,.regular,true)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:false)
        descriptor.usage = .shaderRead; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor:descriptor) else { return nil }
        texture.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:data,bytesPerRow:width*4)
        if textures.count > 192 { textures = [:] }; textures[key] = texture; return texture
    }
    private func refreshAccessibility() {
        let ids = Set(cards.map(\.id)); accessibilityNodes = accessibilityNodes.filter { ids.contains($0.key) }
        for card in cards {
            let node = accessibilityNodes[card.id] ?? MetalTopologyAX()
            node.setAccessibilityRole(.button); node.setAccessibilityEnabled(true)
            node.setAccessibilityLabel(card.accessibilityLabel); node.setAccessibilityParent(self)
            node.press = { [weak self] in self?.onSelect(card.id) }; accessibilityNodes[card.id] = node
        }
        updateAXFrames()
    }
    private func updateAXFrames() {
        guard let window else { return }
        for card in cards {
            let rect = card.isRail ? card.frame : camera.screen(card.frame,in:mainViewport)
            accessibilityNodes[card.id]?.setAccessibilityFrame(window.convertToScreen(convert(rect,to:nil)))
        }
    }
    override func accessibilityChildren() -> [Any]? { cards.compactMap { accessibilityNodes[$0.id] } }
    private func item(at point:CGPoint) -> MetalTopologyID? {
        cards.reversed().first { card in
            if card.isRail { return point.x < mainViewport.minX && card.frame.contains(point) }
            return mainViewport.contains(point) && camera.screen(card.frame,in:mainViewport).contains(point)
        }?.id
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self); let point = convert(event.locationInWindow,from:nil)
        dragPoint = point; pendingClick = item(at:point); dragged = false
    }
    override func mouseDragged(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        guard let previous = dragPoint,point.x >= mainViewport.minX else { return }
        if hypot(point.x-previous.x,point.y-previous.y)>2 { dragged = true }
        onManual(); camera.pan(CGPoint(x:point.x-previous.x,y:point.y-previous.y)); dragPoint = point; draw()
    }
    override func mouseUp(with event:NSEvent) { if !dragged,let pendingClick { onSelect(pendingClick) }; dragPoint = nil; pendingClick = nil }
    override func scrollWheel(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        if point.x < mainViewport.minX {
            let count = cards.filter(\.isRail).count,maxOffset = max(0,CGFloat(count)*100-bounds.height+16)
            let change = event.scrollingDeltaY*(event.hasPreciseScrollingDeltas ? 1 : 16),next = max(0,min(maxOffset,railOffset-change)),delta = next-railOffset
            railOffset = next; cards = cards.map { var item = $0; if item.isRail { item = MetalTopologyCard(id:item.id,frame:item.frame.offsetBy(dx:0,dy:-delta),title:item.title,badge:item.badge,text:item.text,footnote:item.footnote,selected:item.selected,current:item.current,isRail:true) }; return item }
        } else {
            onManual()
            if event.modifierFlags.contains(.command) { camera.zoom(exp(event.scrollingDeltaY*0.025),at:point,in:mainViewport) }
            else { let factor:CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16; camera.pan(CGPoint(x:event.scrollingDeltaX*factor,y:event.scrollingDeltaY*factor)) }
        }
        draw()
    }
    override func magnify(with event:NSEvent) { onManual(); camera.zoom(1+event.magnification,at:convert(event.locationInWindow,from:nil),in:mainViewport); draw() }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 36,let id = cards.last(where: { !$0.isRail })?.id { onSelect(id) }
        else if [123,124,125,126].contains(event.keyCode) {
            onManual(); camera.pan(CGPoint(x:event.keyCode == 123 ? 48 : event.keyCode == 124 ? -48 : 0,y:event.keyCode == 126 ? 48 : event.keyCode == 125 ? -48 : 0)); draw()
        } else { super.keyDown(with:event) }
    }
    /// Exercise the exact render encoder offscreen; tests can verify actual GPU output and failures.
    func renderOffscreen() throws -> (bytes:[UInt8],width:Int,height:Int) {
        guard rendererFailure == nil,let device,let commands else { throw Failure(rendererFailure ?? "Metal unavailable") }
        let width = max(1,Int(bounds.width*2)),height = max(1,Int(bounds.height*2))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:colorPixelFormat,width:width,height:height,mipmapped:false)
        descriptor.usage = [.renderTarget,.shaderRead]; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor:descriptor),let buffer = commands.makeCommandBuffer() else { throw Failure("Metal offscreen allocation failed") }
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = texture
        encode(pass:pass,buffer:buffer,renderSize:CGSize(width:width,height:height)); buffer.commit(); buffer.waitUntilCompleted()
        if let error = buffer.error { throw error }
        var bytes = [UInt8](repeating:0,count:width*height*4)
        texture.getBytes(&bytes,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)
        return (bytes,width,height)
    }
    private static func triangle(_ a:CGPoint,_ b:CGPoint,_ c:CGPoint,color:SIMD4<Float>) -> [Vertex] { [a,b,c].map { Vertex(position:SIMD2(Float($0.x),Float($0.y)),uv:.zero,color:color) } }
    private static func quad(_ rect:CGRect,color:SIMD4<Float>) -> [Vertex] {
        let points:[(CGFloat,CGFloat)] = [(0,0),(1,0),(0,1),(1,0),(1,1),(0,1)]
        return points.map { x,y in Vertex(position:SIMD2(Float(rect.minX+x*rect.width),Float(rect.minY+y*rect.height)),uv:SIMD2(Float(x),Float(y)),color:color) }
    }
    private static func rounded(_ rect:CGRect,radius:CGFloat,color:SIMD4<Float>) -> [Vertex] {
        var outline:[CGPoint] = []
        let centers = [CGPoint(x:rect.maxX-radius,y:rect.minY+radius),CGPoint(x:rect.maxX-radius,y:rect.maxY-radius),CGPoint(x:rect.minX+radius,y:rect.maxY-radius),CGPoint(x:rect.minX+radius,y:rect.minY+radius)]
        for (index,c) in centers.enumerated() { for step in 0...8 { let angle = -Double.pi/2+Double(index)*Double.pi/2+Double(step)*Double.pi/16; outline.append(CGPoint(x:c.x+radius*cos(angle),y:c.y+radius*sin(angle))) } }
        let center = CGPoint(x:rect.midX,y:rect.midY)
        return zip(outline,Array(outline.dropFirst())+[outline[0]]).flatMap { triangle(center,$0,$1,color:color) }
    }
    private static func line(_ a:CGPoint,_ b:CGPoint,width:CGFloat,color:SIMD4<Float>) -> [Vertex] {
        let length = max(0.001,hypot(b.x-a.x,b.y-a.y)),dx = -(b.y-a.y)/length*width/2,dy = (b.x-a.x)/length*width/2
        let p = CGPoint(x:a.x+dx,y:a.y+dy),q = CGPoint(x:a.x-dx,y:a.y-dy),r = CGPoint(x:b.x+dx,y:b.y+dy),s = CGPoint(x:b.x-dx,y:b.y-dy)
        return triangle(p,q,r,color:color)+triangle(q,s,r,color:color)
    }
    private static func connection(_ a:CGRect,_ b:CGRect) -> [CGPoint] {
        if abs(a.minY-b.minY)<1 { let right = b.midX>a.midX; return [CGPoint(x:right ? a.maxX : a.minX,y:a.midY),CGPoint(x:right ? b.minX : b.maxX,y:b.midY)] }
        let y = (a.maxY+b.minY)/2
        return [CGPoint(x:a.midX,y:a.maxY),CGPoint(x:a.midX,y:y),CGPoint(x:b.midX,y:y),CGPoint(x:b.midX,y:b.minY)]
    }
    private static func pathPoint(_ points:[CGPoint],progress:Double) -> CGPoint {
        let lengths = zip(points,points.dropFirst()).map { hypot($1.x-$0.x,$1.y-$0.y) }; var distance = lengths.reduce(0,+)*progress
        for (index,length) in lengths.enumerated() { if distance <= length { let t = distance/max(0.001,length),a = points[index],b = points[index+1]; return CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t) }; distance -= length }
        return points.last ?? .zero
    }
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float2 position; float2 uv; float4 color; };
    struct U { float4 viewport; float4 transform; };
    struct Out { float4 position [[position]]; float2 uv; float4 color; };
    vertex Out topologyVertex(uint id [[vertex_id]],const device V *vertices [[buffer(0)]],constant U &u [[buffer(1)]]) {
        V v=vertices[id]; float2 p=v.position*u.transform.z+u.transform.xy;
        Out o; o.position=float4(p.x/u.viewport.x*2-1,1-p.y/u.viewport.y*2,0,1); o.uv=v.uv; o.color=v.color; return o;
    }
    fragment float4 topologySolid(Out in [[stage_in]]) { return in.color; }
    fragment float4 topologyText(Out in [[stage_in]],texture2d<float> glyphs [[texture(0)]]) {
        constexpr sampler s(filter::linear,address::clamp_to_edge); return glyphs.sample(s,in.uv)*in.color;
    }
    """
}
