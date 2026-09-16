"""Convert official OA-23081 XLSX. Requires pyproj; input path is argv[1]."""
import collections
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile
from pyproj import Transformer

source = Path(sys.argv[1])
ns = {'x': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
with zipfile.ZipFile(source) as z:
    strings = [''.join(e.itertext()) for e in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('x:si', ns)]
    rows = ET.fromstring(z.read('xl/worksheets/sheet1.xml')).findall('x:sheetData/x:row', ns)
    def values(row):
        result = {}
        for c in row:
            v = c.findtext('x:v', default='', namespaces=ns)
            result[''.join(filter(str.isalpha, c.attrib['r']))] = strings[int(v)] if c.get('t') == 's' else v
        return result
    assert values(rows[0])['C'] == '횡단보도관리번호'
    assert values(rows[0])['H'] == 'X좌표'
    transform = Transformer.from_crs(5186, 4326, always_xy=True)
    output, excluded, seen = [], collections.Counter(), set()
    for raw in rows[1:]:
        r = values(raw)
        try:
            lon, lat = transform.transform(float(r['H']), float(r['I']))
        except (ValueError, KeyError):
            excluded['missing_coordinates'] += 1
            continue
        if not (37.3 < lat < 37.8 and 126.7 < lon < 127.3):
            excluded['outside_seoul_bounds'] += 1
            continue
        identity = r.get('C', '')
        if not identity or identity in seen:
            excluded['missing_or_duplicate_id'] += 1
            continue
        seen.add(identity)
        output.append(dict(id=identity, district=r.get('B',''), intersectionID=r.get('D',''),
                           name=r.get('G',''), signalPresence=r.get('F',''),
                           latitude=round(lat,7), longitude=round(lon,7)))
result = dict(source='https://data.seoul.go.kr/dataList/OA-23081/F/1/datasetView.do',
              sourceDate='2026-08-24', publishedDate='2026-09-07', sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),
              coordinateNote='EPSG:5186 inferred from related T-GIS official datasets; OA-23081 does not state CRS explicitly. Verify before signal matching.',
              sourceRows=len(rows)-1, excluded=dict(excluded), crosswalks=output)
Path('GrunnY/Resources/SeoulCrosswalks.json').write_text(json.dumps(result, ensure_ascii=False, separators=(',',':')))
print('Rows:', len(rows)-1, 'included:', len(output), 'excluded:', dict(excluded))
print('City hall samples:', [(p['name'],p['latitude'],p['longitude']) for p in output if '시청' in p['name']][:5])
