"""Portable JevNative identity and fresh bundle assembly; no signing or installation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import struct


class ContractError(Exception):
    pass


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def direct(path):
    path = Path(path).absolute()
    if '..' in path.parts:
        raise ContractError('Product paths must be direct paths without parent traversal')
    if any(p.is_symlink() for p in [*path.parents, path]):
        raise ContractError('Product path alias is forbidden')
    return path


def read_json(path):
    path = direct(path)
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    value = json.loads(data)
    if sha(path) != digest:
        raise ContractError('JSON contract bytes changed during reading')
    return value, digest


def load(root):
    root = direct(root)
    path = direct(root / 'Product.json')
    value, digest = read_json(path)
    keys = {'schema', 'product', 'version', 'build', 'bundleIdentifier', 'executable', 'canonicalSource'}
    if set(value) != keys or (type(value['schema']) is not int or value['schema'] != 1) or value['product'] != 'JevNative':
        raise ContractError('Unsupported product manifest schema or fields')
    if value['canonicalSource'] != '.' or not (root / '.git').is_dir():
        raise ContractError('Build from the Git checkout containing Product.json')
    if value['executable'] != 'jev-native' or value['bundleIdentifier'] != 'com.oozoofrog.JevComputerUse':
        raise ContractError('Product executable/bundle identifier changed')
    if not isinstance(value['build'], str) or not value['build'].isdigit():
        raise ContractError('Expected a numeric build string')
    if not isinstance(value['version'], str) or re.fullmatch(r'\d+(?:\.\d+){0,2}', value['version']) is None:
        raise ContractError('Expected a numeric product version')
    return value, digest


def identity(root):
    value, digest = load(root)
    return {k: value[k] for k in ['schema', 'product', 'version', 'build', 'bundleIdentifier', 'executable']} | {'manifestSHA256': digest}


def generated(root):
    value = identity(root)
    lines = ['// Generated from Product.json by Scripts/product_contract.py. Do not edit.', 'enum CompiledProduct {']
    for key, item in value.items():
        if key == 'schema':
            lines.append(f'    static let {key} = {item}')
        else:
            lines.append(f'    static let {key} = {json.dumps(item)}')
    return '\n'.join(lines + ['}', ''])


def check_generated(root):
    path = direct(Path(root) / 'Sources/JevComputerUse/CompiledProduct.swift')
    if path.read_text() != generated(root):
        raise ContractError('Compiled identity is stale; generate it before building')


def input_digest(inputs):
    return hashlib.sha256(json.dumps(inputs, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def check_bundle(app, root):
    app = direct(app)
    expected = identity(root)
    check_generated(root)
    info = plistlib.loads(direct(app / 'Contents/Info.plist').read_bytes())
    resource = json.loads(direct(app / 'Contents/Resources/ProductIdentity.json').read_text())
    if resource != expected or any(info.get(k) != v for k, v in {
        'CFBundleIdentifier': expected['bundleIdentifier'], 'CFBundleExecutable': expected['executable'],
        'CFBundleShortVersionString': expected['version'], 'CFBundleVersion': expected['build']}.items()):
        raise ContractError('App/compiled product identity differs from Product.json')
    if info.get('LSUIElement') is not True:
        raise ContractError('Native command helpers require an agent bundle; GUI explicitly becomes regular')
    if info.get('LSEnvironment') != {'JEV_GUI_LAUNCH_ORIGIN': 'launchservices'}:
        raise ContractError('GUI default launch requires the signed LaunchServices routing marker')
    return expected


def check_runtime(app, root, run):
    expected = check_bundle(app, root)
    binary = direct(Path(app) / 'Contents/MacOS/jev-native')
    result = run([str(binary), '--version-json'])
    actual = json.loads(result.stdout)
    if any(actual.get(k) != v for k, v in expected.items()) or actual.get('canonicalExecutable') != str(binary):
        raise ContractError('Executable identity differs from app/source identity')
    return {'identity': expected, 'executable_sha256': sha(binary), 'runtime': actual}


def code_digest(path):
    """Compare every pre-signature byte, normalizing only signature-owned size fields."""
    data = path.read_bytes()
    if len(data) < 32 or struct.unpack_from('<I', data)[0] != 0xFEEDFACF:
        raise ContractError('Expected a thin little-endian Mach-O64')
    magic, cpu, subtype, kind, count, cmdsize, flags, reserved = struct.unpack_from('<IiiIIIII', data)
    if cpu != 0x100000C or kind != 2 or cmdsize > len(data) - 32:
        raise ContractError('Expected an arm64 executable with valid load commands')
    normalized = bytearray(data)
    cursor = 32
    sig = None
    linkedit = False
    for _ in range(count):
        if cursor + 8 > 32 + cmdsize:
            raise ContractError('Truncated load command')
        cmd, size = struct.unpack_from('<II', data, cursor)
        if size < 8 or cursor + size > 32 + cmdsize:
            raise ContractError('Invalid load command size')
        if cmd == 0x1D:
            if sig is not None or size != 16:
                raise ContractError('Expected exactly one code-signature command')
            offset, length = struct.unpack_from('<II', data, cursor + 8)
            if offset < 32 + cmdsize or offset + length > len(data):
                raise ContractError('Invalid code signature extent')
            sig = offset
            normalized[cursor + 8:cursor + 16] = b'\0' * 8
        if cmd == 0x19:
            if size < 72:
                raise ContractError('Invalid segment64 command')
            if data[cursor + 8:cursor + 24].rstrip(b'\0') == b'__LINKEDIT':
                if linkedit:
                    raise ContractError('Duplicate LINKEDIT segment')
                linkedit = True
                normalized[cursor + 32:cursor + 40] = b'\0' * 8  # vmsize
                normalized[cursor + 48:cursor + 56] = b'\0' * 8  # filesize
        cursor += size
    if cursor != 32 + cmdsize or sig is None or not linkedit:
        raise ContractError('Expected a complete signed Mach-O command table')
    return {'signature_offset': sig, 'normalized_pre_signature_sha256': hashlib.sha256(normalized[:sig]).hexdigest()}

def provenance(candidate, root, inputs):
    path = direct(Path(candidate).parent / 'build-provenance.json')
    data, digest = read_json(path)
    expected = {'schema': 1, 'canonicalSource': str(direct(root)),
                'identity': identity(root), 'buildInputsSHA256': input_digest(inputs)}
    if any(data.get(k) != v for k, v in expected.items()):
        raise ContractError('Build provenance/source/input identity mismatch')
    if not isinstance(data.get('rawExecutableSHA256'), str) or len(data['rawExecutableSHA256']) != 64:
        raise ContractError('Missing compiled raw executable provenance')
    if not isinstance(data.get('rawCodeDigest'), dict) or set(data['rawCodeDigest']) != {'signature_offset', 'normalized_pre_signature_sha256'}:
        raise ContractError('Missing raw code lineage')
    return {'path': str(path), 'sha256': digest, 'data': data}


def certified(candidate, root, inputs):
    source = provenance(candidate, root, inputs)
    path = direct(Path(candidate).parent / 'certified-build.json')
    recorded, digest = read_json(path)
    executable = direct(Path(candidate) / 'Contents/MacOS/jev-native')
    expected = {'schema': 1, 'provenanceSHA256': source['sha256'],
                'signedExecutableSHA256': sha(executable), 'codeDigest': code_digest(executable)}
    if recorded != expected or recorded['codeDigest'] != source['data']['rawCodeDigest']:
        raise ContractError('Certified/raw code lineage or signed executable changed')
    return {'path': str(path), 'sha256': digest, 'data': recorded}


def assemble(root, candidate, raw, inputs):
    import shutil
    expected = identity(root)
    check_generated(root)
    candidate, raw = direct(candidate), direct(raw)
    parent = candidate.parent
    if candidate.exists() or not parent.is_dir() or (parent / 'build-provenance.json').exists():
        raise ContractError('Expected a fresh candidate in an existing fresh staging directory')
    (candidate / 'Contents/MacOS').mkdir(parents=True)
    resources = candidate / 'Contents/Resources'
    (resources / 'skills/jev-native').mkdir(parents=True)
    shutil.copy2(raw, candidate / 'Contents/MacOS/jev-native')
    shutil.copy2(Path(root) / 'Assets/JevNative.icns', resources / 'JevNative.icns')
    shutil.copy2(Path(root) / 'skill/jev-native/SKILL.md', resources / 'skills/jev-native/SKILL.md')
    (resources / 'ProductIdentity.json').write_text(json.dumps(expected, indent=2) + '\n')
    info = {'CFBundleIdentifier': expected['bundleIdentifier'], 'CFBundleName': 'JEV Native',
            'CFBundleDisplayName': 'JEV Native', 'CFBundleExecutable': expected['executable'],
            'CFBundleIconFile': 'JevNative.icns', 'CFBundlePackageType': 'APPL',
            'CFBundleVersion': expected['build'], 'CFBundleShortVersionString': expected['version'],
            'LSMinimumSystemVersion': '14.0', 'NSPrincipalClass': 'NSApplication', 'LSUIElement': True,
            'LSEnvironment': {'JEV_GUI_LAUNCH_ORIGIN': 'launchservices'},
            'NSCalendarsFullAccessUsageDescription': '승인한 행사 일정을 저장하고 다시 읽어 날짜·시간·장소가 맞는지 확인합니다.'}
    (candidate / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    data = {'schema': 1, 'canonicalSource': str(direct(root)), 'identity': expected,
            'buildInputsSHA256': input_digest(inputs), 'rawExecutableSHA256': sha(raw), 'rawCodeDigest': code_digest(raw)}
    destination = parent / 'build-provenance.json'
    with destination.open('x') as out:
        out.write(json.dumps(data, indent=2) + '\n')
    check_bundle(candidate, root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['generate', 'check', 'assemble'])
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--raw', type=Path)
    parser.add_argument('--inputs', type=Path)
    args = parser.parse_args()
    load(args.root)
    if args.command == 'generate':
        path = direct(args.root / 'Sources/JevComputerUse/CompiledProduct.swift')
        text = generated(args.root)
        if not path.exists() or path.read_text() != text:
            path.write_text(text)
    elif args.command == 'assemble':
        if args.candidate is None or args.raw is None or args.inputs is None:
            parser.error('assemble requires candidate, raw and inputs')
        assemble(args.root, args.candidate, args.raw, json.loads(direct(args.inputs).read_text()))
    else:
        check_generated(args.root)
    print(json.dumps(identity(args.root), indent=2))


if __name__ == '__main__':
    main()
