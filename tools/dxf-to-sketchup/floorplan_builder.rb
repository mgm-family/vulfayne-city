# floorplan_builder.rb
#
# DXFの間取り図から3Dモデルを組み立てるコア処理。
# SketchUp Ruby API に依存するが、入力元(自前DXFパーサー / SketchUp純正
# インポート後のジオメトリ)には依存しない。どちらの経路から呼び出しても
# 同じロジックで壁・建具開口・家具を生成する。
#
# 入力の正規化フォーマット(このモジュールが受け取る形):
#   walls:     [{ points: [Geom::Point3d, ...], closed: false, label: '' }, ...]
#   doors:     [{ points: [Geom::Point3d, ...], closed: bool, label: '' }, ...]
#   windows:   同上
#   furniture: [{ points: [Geom::Point3d, ...], closed: true,  label: '' }, ...]
#
# points はモデル単位(インチ, SketchUp内部単位)のGeom::Point3dであること。
# label は家具の高さ判定・除外判定に使うキーワード文字列(ブロック名やレイヤー名など)。
module FloorplanBuilder
  # ------------------------------------------------------------------
  # 調整用パラメータ。現場の図面に合わせてここを直接編集する。
  # ------------------------------------------------------------------
  CONFIG = {
    wall_height_mm: 2400,          # 壁の立ち上げ高さ(FLからの高さ)
    wall_thickness_mm: 150,        # ★壁厚: DXFに厚み情報がない場合のデフォルト値。
                                    #   実際の壁厚と異なる場合は要調整。壁ごとに
                                    #   厚みを変えたい場合は build_walls の
                                    #   thickness_for.call を編集する。
    wall_representation: :centerline, # :centerline (壁の中心線1本) or
                                    #   :outline (壁の内外形状が閉じたポリラインで
                                    #   表現されている場合)。DXFの描き方に応じて
                                    #   切り替えること。判別が付かない場合は
                                    #   :centerline を既定とする。

    door_height_mm: 2100,          # 扉開口の高さ(床から上端まで)
    door_default_width_mm: 800,    # 建具に幅情報がない場合のデフォルト
    window_sill_height_mm: 900,    # 窓開口の下端高さ(床から)
    window_head_height_mm: 2000,   # 窓開口の上端高さ(床から)
    window_default_width_mm: 1200,
    opening_overrun_mm: 50,        # ★開口カット用ボリュームを壁面から前後に
                                    #   はみ出させる量。斜め壁や壁厚のばらつきで
                                    #   カットが貫通しない場合はここを増やす。

    furniture_default_height_mm: 750,
    # ラベル(ブロック名/レイヤー名など)に部分一致するキーワードで高さを上書き。
    # 大文字小文字は無視。必要に応じて追加・調整すること。
    furniture_height_overrides_mm: {
      'sofa' => 700, 'ソファ' => 700,
      'bed' => 500, 'ベッド' => 500,
      'table' => 700, 'テーブル' => 700,
      'desk' => 700, '机' => 700,
      'chair' => 850, '椅子' => 850, 'イス' => 850,
      'shelf' => 1800, '棚' => 1800, '本棚' => 1800,
      'toilet' => 400, '便器' => 400, 'トイレ' => 400,
      'bath' => 600, '浴槽' => 600, 'バスタブ' => 600,
      'wash' => 850, '洗面' => 850,
    },
    # ★これらのキーワードを含む家具はベースモデルから除外し、後段でレポートする。
    #   (要件: キッチン等の複雑形状は無理に自動生成せず、別途モデリングを提案する)
    excluded_furniture_keywords: [
      'kitchen', 'キッチン', 'sink', 'シンク', 'stove', 'コンロ',
      'range', 'ih', '冷蔵庫', 'refrigerator', 'oven', 'オーブン',
      'counter', 'カウンター', 'unit bath', 'ユニットバス', 'システムキッチン',
    ],
  }.freeze

  module_function

  def mm(v)
    v.to_f.mm # SketchUpのNumeric#mmでモデル単位(インチ)に変換
  end

  # --------------------------------------------------------------
  # 壁の生成: セグメントごとにソリッド(箱)を作り、Solid Toolsの
  # union で結合することでT字・十字交差部分を1つのクリーンな
  # ソリッドにまとめる。ミター(留め)角度を手計算する必要がない。
  # --------------------------------------------------------------
  def build_walls(model, walls)
    return nil if walls.empty?

    height = mm(CONFIG[:wall_height_mm])
    container = model.entities.add_group
    container.name = 'Walls'

    solids = []
    walls.each do |wall|
      pts = wall[:points]
      next if pts.length < 2

      thickness = mm(wall[:thickness_mm] || CONFIG[:wall_thickness_mm])
      segments = pts.each_cons(2).to_a
      segments.each do |p1, p2|
        box = extrude_wall_segment(container.entities, p1, p2, thickness, height)
        solids << box if box
      end
    end

    return nil if solids.empty?

    base = solids.shift
    solids.each do |solid|
      begin
        base = base.union(solid) || base
      rescue StandardError => e
        # ★union に失敗した壁は個別ソリッドのまま残る。SketchUpの
        #   「ソリッドインスペクター」拡張機能で該当箇所を手動確認・修復すること。
        warn "[FloorplanBuilder] wall union failed, left as separate solid: #{e.message}"
      end
    end
    base.name = 'WallsSolid'
    base
  end

  def extrude_wall_segment(entities, p1, p2, thickness, height)
    dir = p2 - p1
    return nil if dir.length.zero?

    dir.normalize!
    normal = Geom::Vector3d.new(-dir.y, dir.x, 0)
    normal.length = thickness / 2.0

    a = p1.offset(normal)
    b = p1.offset(normal.reverse)
    c = p2.offset(normal.reverse)
    d = p2.offset(normal)

    grp = entities.add_group
    face = grp.entities.add_face(a, b, c, d)
    return nil unless face

    # 面の法線が下(-Z寄り)を向いていることがあるため、上向きに押し出す
    face.reverse! if face.normal.z.negative?
    face.pushpull(-height)
    grp
  end

  # --------------------------------------------------------------
  # 壁が :outline (内外形状が閉じたポリラインで表現されている)場合の代替経路。
  # 各閉ループをそのまま床面から壁高さまで押し出す。
  # centerline方式より単純だが、開口カット(cut_openings)は同じロジックを流用できる。
  # --------------------------------------------------------------
  def build_walls_from_outlines(model, walls)
    return nil if walls.empty?

    height = mm(CONFIG[:wall_height_mm])
    container = model.entities.add_group
    container.name = 'Walls'

    solids = []
    walls.each do |wall|
      pts = wall[:points]
      next if pts.length < 3

      grp = container.entities.add_group
      face = grp.entities.add_face(pts)
      next unless face

      face.reverse! if face.normal.z.negative?
      face.pushpull(-height)
      solids << grp
    end

    return nil if solids.empty?

    base = solids.shift
    solids.each do |solid|
      begin
        base = base.union(solid) || base
      rescue StandardError => e
        warn "[FloorplanBuilder] wall union failed, left as separate solid: #{e.message}"
      end
    end
    base.name = 'WallsSolid'
    base
  end

  # --------------------------------------------------------------
  # 扉・窓の開口カット。開口の実幅は building要素(door/window)の
  # ジオメトリから、最寄りの壁セグメントの向きは walls から推定する。
  # --------------------------------------------------------------
  def cut_openings(model, walls_solid, openings, walls, kind)
    return unless walls_solid

    height_range = case kind
                    when :door
                      [0, CONFIG[:door_height_mm]]
                    when :window
                      [CONFIG[:window_sill_height_mm], CONFIG[:window_head_height_mm]]
                    else
                      raise ArgumentError, "unknown opening kind: #{kind}"
                    end
    default_width_mm = kind == :door ? CONFIG[:door_default_width_mm] : CONFIG[:window_default_width_mm]

    openings.each do |opening|
      pts = opening[:points]
      next if pts.empty?

      if pts.length >= 2
        center = midpoint(pts.first, pts.last)
        width = pts.first.distance(pts.last)
        wall_dir = (pts.last - pts.first)
      else
        center = pts.first
        width = mm(opening[:width_mm] || default_width_mm)
        wall_dir = nearest_wall_direction(center, walls)
      end
      next if wall_dir.nil? || wall_dir.length.zero?

      wall_dir = wall_dir.clone
      wall_dir.normalize!
      thickness = mm(nearest_wall_thickness(center, walls) || CONFIG[:wall_thickness_mm])

      cut_single_opening(model, walls_solid, center, wall_dir, width, thickness, height_range)
    end
  end

  def cut_single_opening(model, walls_solid, center, wall_dir, width, thickness, height_range_mm)
    sill = mm(height_range_mm[0])
    head = mm(height_range_mm[1])
    h = head - sill
    return if h <= 0

    depth = thickness + mm(CONFIG[:opening_overrun_mm]) * 2
    normal = Geom::Vector3d.new(-wall_dir.y, wall_dir.x, 0)
    normal.length = depth / 2.0
    half_w = wall_dir.clone
    half_w.length = width / 2.0

    base = Geom::Point3d.new(center.x, center.y, center.z + sill)
    a = base.offset(half_w).offset(normal)
    b = base.offset(half_w).offset(normal.reverse)
    c = base.offset(half_w.reverse).offset(normal.reverse)
    d = base.offset(half_w.reverse).offset(normal)

    grp = model.entities.add_group
    face = grp.entities.add_face(a, b, c, d)
    return unless face

    face.reverse! if face.normal.z.negative?
    face.pushpull(-h)

    begin
      walls_solid.subtract(grp)
    rescue StandardError => e
      # ★カットに失敗した開口は手動でSolid Toolsの「削除(Subtract)」を
      #   壁に対して実行するか、位置・厚みを見直すこと。
      warn "[FloorplanBuilder] opening cut failed near #{center}: #{e.message}"
    end
  end

  def nearest_wall_direction(point, walls)
    best = nil
    best_dist = Float::INFINITY
    walls.each do |wall|
      wall[:points].each_cons(2) do |p1, p2|
        d = distance_point_to_segment(point, p1, p2)
        if d < best_dist
          best_dist = d
          best = p2 - p1
        end
      end
    end
    best
  end

  def nearest_wall_thickness(point, walls)
    best = nil
    best_dist = Float::INFINITY
    walls.each do |wall|
      wall[:points].each_cons(2) do |p1, p2|
        d = distance_point_to_segment(point, p1, p2)
        if d < best_dist
          best_dist = d
          best = wall[:thickness_mm]
        end
      end
    end
    best
  end

  def distance_point_to_segment(p, a, b)
    ab = b - a
    return p.distance(a) if ab.length.zero?

    t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / (ab.x**2 + ab.y**2)
    t = t.clamp(0.0, 1.0)
    proj = Geom::Point3d.new(a.x + ab.x * t, a.y + ab.y * t, a.z)
    p.distance(proj)
  end

  def midpoint(a, b)
    Geom::Point3d.new((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, (a.z + b.z) / 2.0)
  end

  # --------------------------------------------------------------
  # 家具の生成。キッチンなど複雑形状は除外し、後でレポートする。
  # --------------------------------------------------------------
  def build_furniture(model, furniture_items)
    container = model.entities.add_group
    container.name = 'Furniture'
    skipped = []
    built = 0

    furniture_items.each do |item|
      label = (item[:label] || '').downcase
      pts = item[:points]

      if excluded?(label)
        skipped << item
        next
      end

      if pts.nil? || pts.length < 3
        skipped << item.merge(reason: 'insufficient geometry (not a closed polygon)')
        next
      end

      height_mm = height_for_label(label)
      begin
        grp = container.entities.add_group
        face = grp.entities.add_face(pts)
        unless face
          skipped << item.merge(reason: 'could not build a planar face')
          next
        end
        face.reverse! if face.normal.z.negative?
        face.pushpull(-mm(height_mm))
        built += 1
      rescue StandardError => e
        skipped << item.merge(reason: e.message)
      end
    end

    [container, skipped, built]
  end

  def excluded?(label)
    CONFIG[:excluded_furniture_keywords].any? { |kw| label.include?(kw.downcase) }
  end

  def height_for_label(label)
    CONFIG[:furniture_height_overrides_mm].each do |kw, h|
      return h if label.include?(kw.downcase)
    end
    CONFIG[:furniture_default_height_mm]
  end
end
