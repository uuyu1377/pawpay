"""Offline regression checks: footprints, route identity and finite meshes."""
import json
import math
from pathlib import Path
import build_board_models as geometry

ROOT = Path(__file__).resolve().parents[1]


def contains(point, polygon):
    x, z = point
    result = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if (a[1] > z) != (b[1] > z) and x < (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]) + a[0]:
            result = not result
    return result


def main():
    for name, count in [('taiwan', 28), ('sky', 22)]:
        data = json.loads((ROOT / f'assets/models/{name}_board.json').read_text())
        route = data['route']
        assert len(route) == count
        assert len(data['buildings']) == 9
        meshes = [data[k] for k in ['base', 'decor', 'paths', 'clouds']] + list(data['buildings'].values())
        for mesh in meshes:
            for face in mesh:
                assert len(face['p']) >= 3
                assert all(len(p) == 3 and all(math.isfinite(v) for v in p) for p in face['p'])
                assert face['m'] in ['tile', 'roof'] or (len(face['m']) == 7 and face['m'].startswith('#'))
        for i, stop in enumerate(route):
            if name == 'taiwan':
                outline = (geometry.ellipse(*geometry.PENGHU, .20, .17, 24, .045) if i == 26
                           else geometry.smooth(geometry.COAST))
                ground = .12
            else:
                group = next(g for g in range(6) if i < sum(p[-1] for p in geometry.SKY[:g + 1]))
                x, ground, z, rx, rz, _ = geometry.SKY[group]
                outline = geometry.ellipse(x, z, rx, rz, 30, .045)
            assert abs(stop[1] - ground - .017) < 1e-9, (name, i, 'floating foundation')
            scale = data['tile_scales'][i] if name == 'taiwan' else 1.0
            assert 0 < scale <= 1
            # Every vertex of every possible building fits on its own land.
            for mesh in data['buildings'].values():
                for face in mesh:
                    for p in face['p']:
                        assert contains((stop[0] + p[0]*scale, stop[2] + p[2]*scale), outline), (name, i, 'off land')
            for j, other in enumerate(route[:i]):
                other_scale = data['tile_scales'][j] if name == 'taiwan' else 1.0
                assert math.hypot(stop[0] - other[0], stop[2] - other[2]) > .10*(scale+other_scale), (name, i, 'overlapping pads')
        if name == 'taiwan':
            assert data['location_names'] == [p[0] for p in geometry.STOPS]
            assert route == [list(p) for p in geometry.geographic_route()]
            assert route[26][0] < min(p[0] for i,p in enumerate(route) if i != 26), 'Penghu must be offshore west'
            assert route[7][2] < route[8][2], 'Pingtung must be north of Kenting'
            assert route[24][0] > route[15][0], 'Nantou must be inland east of Changhua'
            assert route[25][0] > route[13][0], 'Alishan must be east of Chiayi'
            assert route[4][0] > route[16][0], 'Hualien must be east of Taichung'
        print(f'{name}: {count} locations; all building variants on land; foundations separated; meshes valid')


if __name__ == '__main__':
    main()
