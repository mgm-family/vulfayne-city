# run_from_json.rb
#
# floorplan.json (walls/doors/windows/furniture, 単位mm) を読み込み、
# floorplan_builder.rb の共通ロジックで3Dモデルを生成するエントリーポイント。
#
# このJSON形式は image_to_floorplan.py (写真/PNG等ラスター画像からの
# 検出結果)が出力するもの。DXF由来のデータであっても、同じ形式に
# 変換すればこのスクリプトで3D化できる。
#
# 実行方法(SketchUpのRubyコンソールで):
#   dir = 'このフォルダへの絶対パス'
#   load File.join(dir, 'floorplan_builder.rb')
#   load File.join(dir, 'run_from_json.rb')
#   RunFromJson.run('/path/to/floorplan.json')
#
# ★事前に image_to_floorplan.py が書き出す floorplan_debug.png を必ず
#   目視確認すること。ラスター画像からの検出は誤検出・欠落が起こりうるため、
#   このJSONを直接編集して壁の位置・扉と窓の種別(doors/windows配列の
#   どちらに入っているか)・家具の要否を補正してから実行するのが前提。
#
# 2階建てなど複数階を1つのSketchUpモデルに重ねて生成したい場合は、
# z_offset_mm に階高(FLからFLまでの高さ, 例: 1階なら0、2階なら2700など
# 実際の階高に合わせて調整)を指定して、フロアごとに複数回runを呼ぶ:
#   RunFromJson.run('1F.json', z_offset_mm: 0)
#   RunFromJson.run('2F.json', z_offset_mm: 2700)
# ★z_offset_mmの目安(壁高2400mm + 床/天井構造で300mm程度)は建物により
#   異なるため、実際の断面図・階高寸法があればそちらを優先すること。
require 'json'

module RunFromJson
  module_function

  def run(json_path, z_offset_mm: 0)
    unless File.exist?(json_path)
      UI.messagebox("ファイルが見つかりません: #{json_path}")
      return
    end

    data = JSON.parse(File.read(json_path), symbolize_names: true)
    unless data[:unit].to_s == 'mm'
      UI.messagebox("未対応の単位です(mm以外): #{data[:unit].inspect}")
      return
    end

    walls = (data[:walls] || []).map { |w| normalize_wall(w, z_offset_mm) }
    doors = (data[:doors] || []).map { |d| normalize_opening(d, z_offset_mm) }
    windows = (data[:windows] || []).map { |w| normalize_opening(w, z_offset_mm) }
    furniture = (data[:furniture] || []).map { |f| normalize_furniture(f, z_offset_mm) }

    if walls.empty?
      UI.messagebox('壁データが空です。floorplan.jsonの内容を確認してください。')
      return
    end

    model = Sketchup.active_model
    model.start_operation("Floorplan 3D Generation (from JSON, z=#{z_offset_mm}mm)", true)

    walls_solid =
      if FloorplanBuilder::CONFIG[:wall_representation] == :outline
        FloorplanBuilder.build_walls_from_outlines(model, walls)
      else
        FloorplanBuilder.build_walls(model, walls)
      end

    FloorplanBuilder.cut_openings(model, walls_solid, doors, walls, :door)
    FloorplanBuilder.cut_openings(model, walls_solid, windows, walls, :window)

    _furniture_group, skipped, built = FloorplanBuilder.build_furniture(model, furniture)

    model.commit_operation

    lines = []
    lines << "壁: #{walls.size} / 扉: #{doors.size} / 窓: #{windows.size}"
    lines << "家具: 生成 #{built} 件 / 除外・失敗 #{skipped.size} 件"
    unless skipped.empty?
      lines << '除外・失敗した家具の詳細はRubyコンソールを参照してください。'
      skipped.each { |item| puts "skipped furniture: label=#{item[:label]} reason=#{item[:reason] || 'excluded keyword'}" }
    end
    UI.messagebox(lines.join("\n"))
  end

  def normalize_wall(w, z_offset_mm)
    {
      points: (w[:points] || []).map { |p| point_mm(p, z_offset_mm) },
      thickness_mm: w[:thickness_mm],
    }
  end

  # 扉・窓は「線分(両端点)」または「単一点+width_mm」のどちらの表現も許容する
  # (floorplan_builder.rb の cut_openings が両方のケースを処理する)
  def normalize_opening(o, z_offset_mm)
    if o[:points]
      { points: o[:points].map { |p| point_mm(p, z_offset_mm) } }
    else
      pt = point_mm(o[:point], z_offset_mm)
      { points: [pt], width_mm: o[:width_mm] }
    end
  end

  def normalize_furniture(f, z_offset_mm)
    {
      points: (f[:points] || []).map { |p| point_mm(p, z_offset_mm) },
      closed: true,
      label: f[:label].to_s,
    }
  end

  def point_mm(p, z_offset_mm)
    x, y = p
    Geom::Point3d.new(x.to_f.mm, y.to_f.mm, z_offset_mm.to_f.mm)
  end
end
