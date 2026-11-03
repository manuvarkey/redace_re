"""Check exported airframe damage geometry and vessel placement/relative scale."""
import configparser
import json
from pathlib import Path

import numpy as np

from britain_landscape import coast

DATA = Path(__file__).resolve().parents[1] / 'redace/game_data'


def vertices(path):
    doc = json.loads(path.read_text())
    result = []
    for node in doc['nodes']:
        if 'mesh' not in node:
            continue
        assert 'rotation' not in node and 'matrix' not in node
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            accessor = doc['accessors'][primitive['attributes']['POSITION']]
            view = doc['bufferViews'][accessor['bufferView']]
            assert accessor['componentType'] == 5126 and accessor['type'] == 'VEC3'
            buffer = (path.parent / doc['buffers'][view['buffer']]['uri']).read_bytes()
            offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
            values = np.ndarray((accessor['count'], 3), dtype='<f4', buffer=buffer,
                                offset=offset, strides=(view.get('byteStride', 12), 4))
            result.extend(values * node.get('scale', [1, 1, 1]) + node.get('translation', [0, 0, 0]))
    return np.unique(np.round(result, 5), axis=0)


for name in ['spitfire', 'bf109', 'he111']:
    folder = DATA / 'objects/planes' / name
    intact = vertices(folder / f'{name}.gltf')
    for stage in ['damaged1', 'damaged2', 'wreck']:
        assert np.array_equal(intact, vertices(folder / f'{stage}.gltf')), f'{name}/{stage}: bent airframe'
        doc = json.loads((folder / f'{stage}.gltf').read_text())
        if stage != 'wreck':
            assert any(stage in mat['name'] for mat in doc['materials']), f'{name}: missing bullet paint'

mission = configparser.ConfigParser()
mission.read(DATA / 'missions/26/mission.ini')
quays = [(2900, 1350, 650, 55), (3090, 2200, 850, 55),
         (3480, 1830, 55, 770), (2720, 1700, 170, 580)]
counts = {}
footprints = []
for name, expected_length, expected_count in [('britainfreighter', 210, 5), ('britainfishing', 41.6, 16)]:
    v = vertices(DATA / f'objects/ground/{name}/{name}.gltf')
    size = np.ptp(v, axis=0)
    assert abs(size[2] - expected_length) < .01, f'{name}: incorrect scale'
    counts[name] = 0
    for section in mission.values():
        if section.get('name') != name:
            continue
        counts[name] += 1
        pos = np.array(list(map(float, section['pos'].split())))
        forward = np.array(list(map(float, section['at'].split())))
        right = np.array(list(map(float, section['right'].split())))
        samples = [pos + right*x + forward*z for x in [-size[0]/2, 0, size[0]/2]
                   for z in [-size[2]/2, 0, size[2]/2]]
        for p in samples:
            assert p[0] > coast(p[2]), f'{name}: on land at {p}'
            assert not any(abs(p[0]-x) <= w/2 and abs(p[2]-z) <= d/2 for x,z,w,d in quays), f'{name}: on quay'
        # Conservative rotated bounding rectangles must not intersect other vessels.
        samples = np.array(samples)[:, [0, 2]]
        lo, hi = samples.min(axis=0), samples.max(axis=0)
        assert not any(np.all(lo < b) and np.all(hi > a) for a,b in footprints), f'{name}: vessel overlap'
        footprints.append((lo, hi))
    assert counts[name] == expected_count, counts
print('BRITAIN ASSETS PASS: rigid damage geometry, bullet textures, 5 freighters + 16 boats, scale and placement')
