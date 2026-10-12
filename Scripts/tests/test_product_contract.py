"""Portable identity and bundle fixtures; no compiler, signer or app launch."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('product_contract', Path(__file__).resolve().parents[1] / 'product_contract.py')
product = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(product)


class ProductContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'checkout'
        for folder in ['.git', 'Sources/JevComputerUse', 'Assets', 'skill/jev-native', 'dist']:
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        self.manifest = {'schema': 1, 'product': 'JevNative', 'version': '0.9.0', 'build': '32',
                         'bundleIdentifier': 'com.oozoofrog.JevComputerUse', 'executable': 'jev-native', 'canonicalSource': '.'}
        self.write_manifest()
        (self.root / 'Sources/JevComputerUse/CompiledProduct.swift').write_text(product.generated(self.root))
        (self.root / 'Assets/JevNative.icns').write_bytes(b'fixture-icon')
        (self.root / 'skill/jev-native/SKILL.md').write_text('fixture skill')
        self.raw = self.root / 'raw'
        self.raw.write_bytes(b'fixture executable; never executed')
        self.app = self.root / 'dist/JevNative.app'

    def write_manifest(self):
        (self.root / 'Product.json').write_text(json.dumps(self.manifest))

    def assemble(self):
        with patch.object(product, 'code_digest', return_value={'signature_offset': 1, 'normalized_pre_signature_sha256': 'AB' * 32}):
            product.assemble(self.root, self.app, self.raw, {})

    def test_relative_checkout_identity_and_generated_hash(self):
        value = product.identity(self.root)
        self.assertEqual(value['build'], '32')
        self.assertNotIn(str(self.root), product.generated(self.root))
        product.check_generated(self.root)

    def test_absolute_developer_source_rejected(self):
        self.manifest['canonicalSource'] = str(self.root)
        self.write_manifest()
        with self.assertRaises(product.ContractError):
            product.load(self.root)

    def test_stale_compiled_identity_rejected(self):
        self.manifest['build'] = '33'
        self.write_manifest()
        with self.assertRaises(product.ContractError):
            product.check_generated(self.root)

    def test_parent_traversal_and_symlink_rejected(self):
        with self.assertRaises(product.ContractError):
            product.direct(self.root / '..' / 'another')
        link = self.root.parent / 'alias'
        link.symlink_to(self.root)
        with self.assertRaises(product.ContractError):
            product.load(link)

    def test_fresh_bundle_has_exact_identity_and_GUI_marker(self):
        self.assemble()
        self.assertEqual(product.check_bundle(self.app, self.root), product.identity(self.root))
        info = plistlib.loads((self.app / 'Contents/Info.plist').read_bytes())
        self.assertTrue(info['LSUIElement'])
        self.assertEqual(info['LSEnvironment'], {'JEV_GUI_LAUNCH_ORIGIN': 'launchservices'})
        self.assertEqual((self.app / 'Contents/MacOS/jev-native').read_bytes(), self.raw.read_bytes())

    def test_existing_bundle_is_not_replaced(self):
        self.assemble()
        before = (self.app / 'Contents/Info.plist').read_bytes()
        with self.assertRaises(product.ContractError):
            self.assemble()
        self.assertEqual((self.app / 'Contents/Info.plist').read_bytes(), before)

    def test_existing_provenance_blocks_before_bundle_creation(self):
        record = self.app.parent / 'build-provenance.json'
        record.write_text('existing evidence')
        with self.assertRaises(product.ContractError):
            self.assemble()
        self.assertFalse(self.app.exists())
        self.assertEqual(record.read_text(), 'existing evidence')

    def test_modified_bundle_version_rejected(self):
        self.assemble()
        path = self.app / 'Contents/Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['CFBundleVersion'] = '1'
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaises(product.ContractError):
            product.check_bundle(self.app, self.root)


if __name__ == '__main__':
    unittest.main()
