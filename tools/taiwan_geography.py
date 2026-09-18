"""Display-only geography. IDs match _generateTaiwanNodes, never reorder them.

City labels use approximate city-centre coordinates (New Taipei: Banqiao).
Landmarks use their own coordinates; event tiles are fictional locations.
The coastline is simplified for the toy model, not an administrative boundary.
Reference: https://www.taiwan.net.tw/m1.aspx?sno=0000163
"""
import math


def project(lon, lat):
    # Equirectangular map at 23.6 N: east right, north toward negative Z.
    return ((lon - 120.85) * 1.30 * math.cos(math.radians(23.6)),
            (23.60 - lat) * 1.30)


# North coast, east coast, southern tip, west coast (clockwise).
COAST_LON_LAT = [
    (121.52, 25.30), (121.70, 25.23), (121.88, 25.13), (122.00, 25.01),
    (121.92, 24.85), (121.84, 24.66), (121.79, 24.48), (121.68, 24.18),
    (121.63, 23.98), (121.55, 23.72), (121.48, 23.47), (121.40, 23.26),
    (121.30, 23.08), (121.20, 22.89), (121.13, 22.72), (120.99, 22.58),
    (120.89, 22.38), (120.86, 22.16), (120.87, 21.93), (120.83, 21.90),
    (120.74, 21.96), (120.70, 22.09), (120.62, 22.31), (120.45, 22.46),
    (120.27, 22.61), (120.18, 22.78), (120.05, 23.01), (120.04, 23.23),
    (120.13, 23.50), (120.18, 23.73), (120.31, 23.95), (120.49, 24.20),
    (120.65, 24.47), (120.84, 24.70), (120.96, 24.92), (121.17, 25.07),
    (121.38, 25.18),
]
# Small, consistent coastal margin accommodates the buildings on coastal towns.
COAST = [(x * 1.055, z * 1.035) for x, z in map(lambda p: project(*p), COAST_LON_LAT)]

STOPS = [
    ('台北(GO)', 121.5149, 25.0377), ('基隆', 121.7419, 25.1283),
    ('宜蘭', 121.7530, 24.7500), ('機會', 121.7100, 24.3600),
    ('花蓮', 121.6068, 23.9911), ('秀姑巒溪', 121.4900, 23.4600),
    ('台東', 121.1467, 22.7560), ('屏東', 120.4870, 22.6720),
    ('墾丁', 120.7990, 21.9460), ('監獄', 120.6500, 22.2300),
    ('高雄', 120.3010, 22.6270), ('台南', 120.2030, 22.9990),
    ('機會', 120.2200, 23.2500), ('嘉義', 120.4490, 23.4800),
    ('雲林', 120.5350, 23.7100), ('彰化', 120.5440, 24.0750),
    ('台中', 120.6830, 24.1470), ('苗栗', 120.8210, 24.5600),
    ('新竹', 120.9670, 24.8060), ('桃園', 121.3010, 24.9940),
    ('繳稅', 121.2960, 24.6600), ('新北', 121.4630, 25.0120),
    ('101大樓', 121.5650, 25.0340), ('機會', 121.0800, 24.2300),
    ('南投', 120.6850, 23.9150), ('阿里山', 120.8050, 23.5100),
    ('澎湖', 119.5660, 23.5650), ('進監獄', 121.5200, 25.2300),
]
PENGHU = project(119.5660, 23.5650)


def route():
    return [(x, .137, z) for _, lon, lat in STOPS for x, z in [project(lon, lat)]]


def tile_scales(outline):
    """Shrink crowded city buildings, never move their geographic anchors."""
    points = [(p[0], p[2]) for p in route()]
    def edge_distance(p, a, b):
        dx, dz = b[0] - a[0], b[1] - a[1]
        t = max(0., min(1., ((p[0]-a[0])*dx+(p[1]-a[1])*dz)/(dx*dx+dz*dz)))
        return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dz)
    scales = []
    for i, p in enumerate(points):
        neighbour = min(math.dist(p, q) for j, q in enumerate(points) if j != i)
        shore = .18 if i == 26 else min(edge_distance(p, a, b) for a, b in zip(outline, outline[1:]+outline[:1]))
        scales.append(min(1., neighbour / .25, shore / .16))
    return scales
