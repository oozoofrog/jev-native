import Foundation
import Security
import Darwin
let status = SessionCreate(SessionCreationFlags(), SessionAttributeBits())
guard status == errSecSuccess else { fputs("Test security-session creation unavailable: \(status)\n",stderr); exit(77) }
let args=Array(CommandLine.arguments.dropFirst())
guard let exe=args.first else { exit(64) }
let pointers=args.map { strdup($0) } + [nil]
exe.withCString { _ = execv($0,pointers) }
exit(71)
