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
                outline = geometry.smooth(geometry.COAST)
                ground = .12
            else:
                group = next(g for g in range(6) if i < sum(p[-1] for p in geometry.SKY[:g + 1]))
                x, ground, z, rx, rz, _ = geometry.SKY[group]
                outline = geometry.ellipse(x, z, rx, rz, 30, .045)
            assert abs(stop[1] - ground - .017) < 1e-9, (name, i, 'floating foundation')
            # Every vertex of every possible building fits on its own land.
            for mesh in data['buildings'].values():
                for face in mesh:
                    for p in face['p']:
                        assert contains((stop[0] + p[0], stop[2] + p[2]), outline), (name, i, 'off land')
            for other in route[:i]:
                assert math.hypot(stop[0] - other[0], stop[2] - other[2]) > .20, (name, i, 'overlapping pads')
        print(f'{name}: {count} locations; all building variants on land; foundations separated; meshes valid')


if __name__ == '__main__':
    main()
