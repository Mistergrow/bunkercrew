#!/usr/bin/env python3
"""Check annotations against current image bytes, actual light/flow colors and water."""
import hashlib
import json
import unittest
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


class V3Landmarks(unittest.TestCase):
    def test_all_annotations_match_current_images_and_semantic_pixels(self):
        data = json.loads((ROOT / 'assets/environments/v3/landmarks.json').read_text())
        self.assertEqual(len(data['environments']), 13)
        for name, entry in data['environments'].items():
            with self.subTest(environment=name):
                source = ROOT / entry['source']
                digest = hashlib.sha256(source.read_bytes()).hexdigest()
                self.assertEqual(digest, entry['source_sha256'], 'Re-measure annotations after replacing an image')
                original = Image.open(source).convert('RGB')
                self.assertEqual(list(original.size), data['size'])
                rgb = np.asarray(original, dtype=float) / 255
                mask_path = ROOT / 'assets/atmosphere/sky_masks' / (name + '.png')
                metadata = json.loads(mask_path.with_suffix('.source.json').read_text())
                self.assertEqual(metadata['source_sha256'], digest)
                self.assertEqual(metadata['source'], entry['source'])
                mask = Image.open(mask_path)
                self.assertEqual(mask.size, original.size)
                for kind, points in entry['probes'].items():
                    for x, y in points:
                        self.assertEqual(mask.getpixel((x, y)) > 127, kind == 'sky', (name, kind, x, y))
                for x, y, rx, ry, kind in entry['details'].get('lights', []):
                    crop = rgb[y-ry:y+ry, x-rx:x+rx]
                    r, g, b = crop[:,:,0], crop[:,:,1], crop[:,:,2]
                    luminous = (r-np.maximum(g*.95, b*1.14) > .035) & (r > .22)
                    if kind == 'white':
                        luminous |= r*.299+g*.587+b*.114 > .52
                    self.assertGreater(np.count_nonzero(luminous), 2, (name, 'anchor must contain real luminous pixels', x, y))
                    self.assertEqual(mask.getpixel((x,y)), 0, 'A lamp cannot be in open sky')
                for x, y, w, h in entry['details'].get('flows', []):
                    self.assertTrue(0 <= x < x+w <= original.width and 0 <= y < y+h <= original.height)
                    crop = rgb[y:y+h, x:x+w]
                    water = (crop[:,:,2]-crop[:,:,0]*.93 > .012) & (crop @ np.array([.299,.587,.114]) > .20)
                    self.assertGreater(np.mean(water), .1, (name, 'flow must cover painted water'))
                for x, y, _scale, _kind in entry['details'].get('plumes', []):
                    self.assertEqual(mask.getpixel((x,y)), 0, 'A plume must originate on a real landmark')
                for x, y, w, h, _kind in entry['details'].get('banks', []):
                    self.assertEqual(mask.getpixel((int(x+w/2),int(y+h/2))), 0, 'Terrain drift must be below the sky')

    def test_power_station_foam_is_wholly_in_current_water(self):
        catalog = json.loads((ROOT / 'assets/environments/catalog.json').read_text())
        site = next(e for e in catalog['environments'] if e['id']=='flooded_power_station')
        x0,y0,w,h = site['water_regions'][0]
        for x,y,width in site['water_outlets']:
            self.assertGreaterEqual(x-width*.75,x0)
            self.assertLessEqual(x+width*.75,x0+w)
            self.assertGreaterEqual(y-10/941,y0)
            self.assertLessEqual(y+21/941,y0+h)


if __name__ == '__main__':
    unittest.main()
