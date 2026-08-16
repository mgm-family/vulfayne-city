#!/usr/bin/env python3
"""image_to_floorplan.py

写真/PNG/JPGなどラスター画像の間取り図から、壁・扉・窓・家具を
おおまかに検出し、SketchUp生成スクリプト(floorplan_builder.rb)が
読み込める共通JSON形式(walls/doors/windows/furniture、単位mm)に
書き出す前処理ツール。

依存: Python 3 + opencv-python + numpy
    pip install opencv-python numpy

★重要な限界: DXFのようにレイヤー情報を持たないため、画像解析は
あくまで「線の太さ・長さ・隙間・輪郭形状」からの推定(ヒューリスティック)。
CADから書き出したクリーンな線画PNGでは実用的な精度が出るが、
手書き・スマホ写真(照明ムラ/斜め撮影/歪み)は誤検出が増える。
本スクリプトは検出結果を必ず floorplan_debug.png (注釈付き画像)として
書き出すので、SketchUpで3D化する前に目視確認し、必要なら
floorplan.json を直接編集して補正すること。

★スケール(実寸換算)について: 画像だけでは何mmが何pxかは分からない。
以下のいずれかを必ず指定すること:
  --mm-per-px 5.0
      1pxが何mmに相当するかを直接指定
  --reference-px x1,y1,x2,y2 --reference-mm 3640
      画像上の既知の2点(例: 寸法線の両端)のpx座標と、その実寸(mm)を
      指定して自動換算する

使用例:
  python3 image_to_floorplan.py plan.png \
      --reference-px 120,80,120,640 --reference-mm 3640 \
      --out floorplan.json

  # 実寸が不明な場合(検討用の相対スケールでよい場合)は暫定値を使う
  python3 image_to_floorplan.py plan.png --mm-per-px 5.0 --out floorplan.json

その後、SketchUpのRubyコンソールで:
  load 'floorplan_builder.rb'
  load 'run_from_json.rb'
  RunFromJson.run('floorplan.json')
"""
import argparse
import json
import math
import sys

import cv2
import numpy as np


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('image', help='間取り図の画像ファイル(png/jpg等)')
    p.add_argument('--out', default='floorplan.json', help='出力JSONパス(既定: floorplan.json)')
    p.add_argument('--debug-image', default=None, help='注釈付き確認画像の出力パス(既定: <out>を元にした名前)')
    p.add_argument('--mm-per-px', type=float, default=None, help='1pxあたりのmm。--referenceと排他')
    p.add_argument('--reference-px', default=None, help='既知区間の両端px座標 "x1,y1,x2,y2"')
    p.add_argument('--reference-mm', type=float, default=None, help='--reference-pxで指定した区間の実寸(mm)')
    p.add_argument('--photo-mode', action='store_true',
                    help='スマホ写真など、照明ムラ・ノイズが多い入力向けの前処理を強化する')
    p.add_argument('--min-wall-length-px', type=int, default=40,
                    help='壁とみなす最小の線分の長さ(px)。短いと誤検出が増える(既定40)')
    p.add_argument('--furniture-min-area-px2', type=int, default=200,
                    help='家具とみなす輪郭の最小面積(px^2)。ノイズ除去用(既定200)')
    p.add_argument('--furniture-max-area-ratio', type=float, default=0.15,
                    help='画像全体に対する家具輪郭の最大面積比。これを超えると部屋そのものを'
                         '誤検出している可能性が高いため除外(既定0.15)')
    p.add_argument('--max-bridge-gap-px', type=int, default=200,
                    help='同一直線上の壁セグメントを1本に結合する際に許容する'
                         '最大の隙間(px)。扉・窓の開口幅より少し大きい値にする(既定200)')
    return p.parse_args()


def compute_scale(args):
    if args.mm_per_px:
        return args.mm_per_px
    if args.reference_px and args.reference_mm:
        x1, y1, x2, y2 = (float(v) for v in args.reference_px.split(','))
        px_len = math.hypot(x2 - x1, y1 - y2)
        if px_len == 0:
            raise ValueError('--reference-px の2点が同一座標です')
        return args.reference_mm / px_len
    raise ValueError('--mm-per-px か --reference-px/--reference-mm のいずれかを指定してください'
                      '(画像だけでは実寸スケールが分からないため必須)')


def preprocess(img, photo_mode):
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    if photo_mode:
        gray = cv2.bilateralFilter(gray, 9, 60, 60)
        binary = cv2.adaptiveThreshold(
            gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 35, 10
        )
    else:
        _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    return binary


def detect_wall_mask(binary):
    """太い線(=壁)だけを残す。家具や寸法線などの細い線はモルフォロジー
    オープニングで除去する。★構造要素サイズは壁の想定線太さ(px)に依存する
    ため、線が太い/細い図面では kernel_size を調整すること。"""
    # ★壁線の想定太さ(px)に応じて調整すること。目安: 家具・寸法線などの
    #   細線の太さより大きく、壁線の太さ以下の値にする(大きすぎると壁ごと
    #   消えてしまう、小さすぎると細線を壁と誤検出する)。原寸画像の解像度に
    #   よって最適値は変わるため、まず既定値で実行し wall_mask 抜き出し結果を
    #   floorplan_debug.png で確認しながら調整するのが確実。
    kernel_size = 4
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (kernel_size, kernel_size))
    opened = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel, iterations=1)
    closed = cv2.morphologyEx(opened, cv2.MORPH_CLOSE, kernel, iterations=1)
    return closed


def estimate_wall_thickness_px(wall_mask):
    dist = cv2.distanceTransform(wall_mask, cv2.DIST_L2, 5)
    nonzero = dist[wall_mask > 0]
    if nonzero.size == 0:
        return 5.0
    return float(np.mean(nonzero) * 2.0)


def detect_line_segments(mask, min_length_px):
    lines = cv2.HoughLinesP(
        mask, rho=1, theta=np.pi / 180, threshold=40,
        minLineLength=min_length_px, maxLineGap=8
    )
    if lines is None:
        return []
    # OpenCVのバージョンによって shape が (N,1,4) と (N,4) のどちらもあり得るため両対応
    lines = lines.reshape(-1, 4)
    return [tuple(int(v) for v in line) for line in lines]


def angle_of(seg):
    x1, y1, x2, y2 = seg
    return math.atan2(y2 - y1, x2 - x1) % math.pi


def merge_segments(segments, angle_tol=math.radians(4), dist_tol=12, max_bridge_gap_px=200):
    """ほぼ同一直線上にある近接セグメントを1本のポリライン(2点)へ統合する。
    壁は本来1枚の直線壁でも、Hough変換では複数の短い線分に割れて
    検出されがちなため、これをまとめることで build_walls の union が
    安定する。★max_bridge_gap_px: 同一直線上でも、扉・窓の開口幅を超える
    ような大きな隙間がある場合は無関係な壁として結合しない上限(px)。
    これがないと、たまたま同一直線上にある離れた壁同士まで誤って
    1本につながってしまう。"""
    remaining = list(segments)
    merged = []

    while remaining:
        seg = remaining.pop(0)
        group = [seg]
        a0 = angle_of(seg)
        changed = True
        while changed:
            changed = False
            still_remaining = []
            for other in remaining:
                a1 = angle_of(other)
                angle_diff = min(abs(a0 - a1), math.pi - abs(a0 - a1))
                if angle_diff <= angle_tol and _segments_close(group, other, dist_tol, max_bridge_gap_px):
                    group.append(other)
                    changed = True
                else:
                    still_remaining.append(other)
            remaining = still_remaining

        merged.append(_collapse_group(group))

    return merged


def _segments_close(group, seg, dist_tol, max_bridge_gap_px):
    for g in group:
        for (gx, gy) in [(g[0], g[1]), (g[2], g[3])]:
            for (sx, sy) in [(seg[0], seg[1]), (seg[2], seg[3])]:
                if math.hypot(gx - sx, gy - sy) <= dist_tol:
                    return True
    # 端点が近くなくても、同一直線の延長線上かつ隙間が上限以内なら結合対象とする
    return _collinear_overlap(group[-1], seg, dist_tol, max_bridge_gap_px)


def _collinear_overlap(a, b, dist_tol, max_bridge_gap_px):
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    dx, dy = ax2 - ax1, ay2 - ay1
    length = math.hypot(dx, dy)
    if length == 0:
        return False
    ux, uy = dx / length, dy / length
    nx, ny = -uy, ux

    def project(px, py):
        t = (px - ax1) * ux + (py - ay1) * uy
        d = abs((px - ax1) * nx + (py - ay1) * ny)
        return t, d

    tb1, db1 = project(bx1, by1)
    tb2, db2 = project(bx2, by2)
    if max(db1, db2) > dist_tol:
        return False  # 直線から離れすぎている

    b_lo, b_hi = min(tb1, tb2), max(tb1, tb2)
    gap = max(0.0 - b_hi, b_lo - length, 0.0)
    return gap <= max_bridge_gap_px


def _collapse_group(group):
    pts = []
    for x1, y1, x2, y2 in group:
        pts.append((x1, y1))
        pts.append((x2, y2))
    # 最も離れた2点をポリラインの両端として採用(単純だが直線壁には十分)
    best = None
    best_d = -1
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            d = math.hypot(pts[i][0] - pts[j][0], pts[i][1] - pts[j][1])
            if d > best_d:
                best_d = d
                best = (pts[i], pts[j])
    return best


def find_gaps_as_openings(wall_mask, merged_walls, gap_search_px=30, min_gap_px=15, max_gap_px=140):
    """壁ポリラインの延長線上にある「隙間」を扉・窓の開口候補として拾う。
    ★これは壁マスクの穴を機械的に探すだけなので、扉と窓の区別は付かない。
    区別は _classify_opening のヒューリスティック(近傍のアーク=扉)に頼るが
    誤判定しうる。生成後の floorplan.json で kind を目視修正することを推奨。"""
    openings = []
    h, w = wall_mask.shape
    for (x1, y1), (x2, y2) in merged_walls:
        length = math.hypot(x2 - x1, y2 - y1)
        if length == 0:
            continue
        ux, uy = (x2 - x1) / length, (y2 - y1) / length
        steps = int(length)
        gap_start = None
        for s in range(0, steps, 2):
            px = int(x1 + ux * s)
            py = int(y1 + uy * s)
            if not (0 <= px < w and 0 <= py < h):
                continue
            is_wall = wall_mask[py, px] > 0
            if not is_wall:
                if gap_start is None:
                    gap_start = (px, py, s)
            else:
                if gap_start is not None:
                    gp_x, gp_y, gs = gap_start
                    gap_len_px = s - gs
                    if min_gap_px <= gap_len_px <= max_gap_px:
                        mid_s = (gs + s) / 2.0
                        mx = x1 + ux * mid_s
                        my = y1 + uy * mid_s
                        openings.append({
                            'center_px': (mx, my),
                            'width_px': gap_len_px,
                            'wall_dir': (ux, uy),
                        })
                    gap_start = None
    return openings


def classify_opening(binary, opening, arc_search_radius_px=60):
    """開口中心付近に扉の開き勝手を示す弧(円弧)状の輪郭がないか探す。
    見つかれば扉、見つからなければ窓と推定する。★誤検出が多いヒューリスティック
    なので、生成されたJSONの"kind"フィールドは必ず目視確認すること。"""
    mx, my = opening['center_px']
    h, w = binary.shape
    x0 = max(0, int(mx - arc_search_radius_px))
    x1 = min(w, int(mx + arc_search_radius_px))
    y0 = max(0, int(my - arc_search_radius_px))
    y1 = min(h, int(my + arc_search_radius_px))
    roi = binary[y0:y1, x0:x1]
    if roi.size == 0:
        return 'window'

    contours, _ = cv2.findContours(roi, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    for c in contours:
        area = cv2.contourArea(c)
        perim = cv2.arcLength(c, False)
        if perim == 0:
            continue
        # 弧は面積に対して周長が長く、閉じた矩形(家具等)ほど"詰まって"いない。
        # ただし壁の切れ端(コーナー)も細長い低circularity値を取りうるため、
        # バウンディングボックスがおおむね正方形(=扇形/円弧らしい拡がり)で
        # あることも合わせて要求し、誤検出を減らしている。
        # ★それでも完全な区別はできないため、door/window の判定は必ず目視確認すること。
        circularity = 4 * math.pi * area / (perim * perim) if area > 0 else 0
        x, y, w, h = cv2.boundingRect(c)
        aspect = min(w, h) / max(w, h) if max(w, h) > 0 else 0
        if perim > 60 and 0.02 < circularity < 0.5 and aspect > 0.6:
            return 'door'
    return 'window'


def detect_furniture(binary, wall_mask, args, img_shape):
    non_wall = cv2.bitwise_and(binary, cv2.bitwise_not(wall_mask))
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
    non_wall = cv2.morphologyEx(non_wall, cv2.MORPH_CLOSE, kernel, iterations=1)

    contours, _ = cv2.findContours(non_wall, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    img_area = img_shape[0] * img_shape[1]
    items = []
    for c in contours:
        area = cv2.contourArea(c)
        if area < args.furniture_min_area_px2:
            continue
        if area / img_area > args.furniture_max_area_ratio:
            continue  # 部屋全体など巨大輪郭の誤検出を除外
        eps = 0.01 * cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, eps, True)
        pts = [(float(p[0][0]), float(p[0][1])) for p in approx]
        if len(pts) < 3:
            continue
        # 頂点数が多い(=形状が複雑)ものは、キッチン什器などDXFワークフローの
        # "excluded_furniture_keywords"に相当する要注意アイテムとしてフラグを立てる。
        # 画像からは名称が分からないため、ラベルは "unknown" とし、SketchUp側の
        # デフォルト高さ(750mm)で仮生成される。手動で高さ・要否を見直すこと。
        complex_shape = len(pts) >= 8
        items.append({'points': pts, 'complex': complex_shape})
    return items


def to_mm(pt_px, mm_per_px, img_height):
    x_px, y_px = pt_px
    # 画像座標(左上原点、Y下向き)→ 平面図座標(左下原点、Y上向き)に変換
    return [x_px * mm_per_px, (img_height - y_px) * mm_per_px]


def build_debug_image(img, merged_walls, openings, furniture_items):
    out = img.copy()
    for (p1, p2) in merged_walls:
        cv2.line(out, (int(p1[0]), int(p1[1])), (int(p2[0]), int(p2[1])), (0, 0, 255), 3)
    for o in openings:
        cx, cy = o['center_px']
        color = (0, 200, 0) if o['kind'] == 'door' else (255, 128, 0)
        cv2.circle(out, (int(cx), int(cy)), 10, color, 3)
    for item in furniture_items:
        pts = np.array(item['points'], dtype=np.int32).reshape(-1, 1, 2)
        color = (0, 0, 0) if item['complex'] else (0, 200, 200)
        cv2.polylines(out, [pts], True, color, 2)
    return out


def main():
    args = parse_args()
    mm_per_px = compute_scale(args)

    img = cv2.imread(args.image)
    if img is None:
        print(f'error: could not read image: {args.image}', file=sys.stderr)
        sys.exit(1)
    img_h = img.shape[0]

    binary = preprocess(img, args.photo_mode)
    wall_mask = detect_wall_mask(binary)
    thickness_px = estimate_wall_thickness_px(wall_mask)

    raw_segments = detect_line_segments(wall_mask, args.min_wall_length_px)
    merged = merge_segments(raw_segments, max_bridge_gap_px=args.max_bridge_gap_px)

    openings_raw = find_gaps_as_openings(wall_mask, merged)
    openings = []
    for o in openings_raw:
        kind = classify_opening(binary, o)
        o['kind'] = kind
        openings.append(o)

    furniture_items = detect_furniture(binary, wall_mask, args, img.shape)

    debug_img = build_debug_image(img, merged, openings, furniture_items)
    debug_path = args.debug_image or (args.out.rsplit('.', 1)[0] + '_debug.png')
    cv2.imwrite(debug_path, debug_img)

    data = {
        'unit': 'mm',
        'source_image': args.image,
        'mm_per_px': mm_per_px,
        'walls': [
            {
                'points': [to_mm(p1, mm_per_px, img_h), to_mm(p2, mm_per_px, img_h)],
                'thickness_mm': round(thickness_px * mm_per_px, 1),
            }
            for (p1, p2) in merged
        ],
        'doors': [
            {
                'point': to_mm(o['center_px'], mm_per_px, img_h),
                'width_mm': round(o['width_px'] * mm_per_px, 1),
            }
            for o in openings if o['kind'] == 'door'
        ],
        'windows': [
            {
                'point': to_mm(o['center_px'], mm_per_px, img_h),
                'width_mm': round(o['width_px'] * mm_per_px, 1),
            }
            for o in openings if o['kind'] == 'window'
        ],
        'furniture': [
            {
                'points': [to_mm(p, mm_per_px, img_h) for p in item['points']],
                'label': 'unknown_complex' if item['complex'] else 'unknown',
            }
            for item in furniture_items
        ],
    }

    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f'walls: {len(data["walls"])}, doors: {len(data["doors"])}, '
          f'windows: {len(data["windows"])}, furniture: {len(data["furniture"])}')
    print(f'wrote {args.out}')
    print(f'wrote {debug_path} (SketchUpで生成する前に必ず目視確認すること)')
    complex_count = sum(1 for it in furniture_items if it['complex'])
    if complex_count:
        print(f'note: {complex_count} 件の家具が複雑な輪郭として検出されました。'
              f'キッチン等の可能性があるため floorplan.json の label を確認し、'
              f'必要ならエントリを削除して別途モデリングすることを推奨します。')


if __name__ == '__main__':
    main()
