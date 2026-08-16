# run_from_dxf.rb
#
# 実行方法(SketchUpのRubyコンソールで):
#   dir = 'このフォルダへの絶対パス'
#   load File.join(dir, 'dxf_parser.rb')
#   load File.join(dir, 'floorplan_builder.rb')
#   load File.join(dir, 'run_from_dxf.rb')
#   RunFromDxf.run
#
# ファイル選択ダイアログでDXFを指定すると、このスクリプト自身がDXFテキストを
# 読み取り(dxf_parser.rb)、壁の立ち上げ・建具開口カット・家具生成
# (floorplan_builder.rb)までを一括で行う。
#
# ★DXFに円弧・スプラインが含まれる場合はdxf_parser.rbが対応していないため、
#   事前にCAD側で直線・ポリラインへ分解しておくこと。それが難しい場合は
#   run_from_native_import.rb (SketchUp純正のDXFインポート機能を使う方式)
#   を使うほうが確実。
module RunFromDxf
  # DXFの図面単位 → mm への倍率。
  # ★多くの建築DXFはmm単位だが、mではない場合はここを変更する
  #   (例: 図面単位がメートルなら 1000.0、インチなら 25.4)。
  DXF_UNIT_TO_MM = 1.0

  LAYER_MATCHERS = {
    walls: /wall/i,
    doors: /door/i,
    windows: /window/i,
    furniture: /furniture/i,
  }.freeze

  module_function

  def run
    dxf_path = UI.openpanel('間取り図DXFファイルを選択', '', 'DXF Files|*.dxf||')
    return unless dxf_path

    raw_entities = DxfParser.parse(dxf_path)
    if raw_entities.empty?
      UI.messagebox('DXFからエンティティを読み取れませんでした。ファイル形式(ASCII DXF)を確認してください。')
      return
    end

    grouped = { walls: [], doors: [], windows: [], furniture: [] }
    raw_entities.each do |ent|
      category = LAYER_MATCHERS.find { |_k, re| ent.layer =~ re }&.first
      next unless category

      grouped[category] << normalize(ent)
    end

    model = Sketchup.active_model
    model.start_operation('Floorplan 3D Generation (from DXF)', true)

    walls_solid =
      if FloorplanBuilder::CONFIG[:wall_representation] == :outline
        FloorplanBuilder.build_walls_from_outlines(model, grouped[:walls])
      else
        FloorplanBuilder.build_walls(model, grouped[:walls])
      end

    FloorplanBuilder.cut_openings(model, walls_solid, grouped[:doors], grouped[:walls], :door)
    FloorplanBuilder.cut_openings(model, walls_solid, grouped[:windows], grouped[:walls], :window)

    _furniture_group, skipped, built = FloorplanBuilder.build_furniture(model, grouped[:furniture])

    model.commit_operation

    report(dxf_path, grouped, built, skipped)
  end

  # DXFの生座標(mm換算前)をモデル単位のGeom::Point3dに変換した正規化ハッシュへ
  def normalize(entity)
    pts = (entity.points || []).map do |p|
      next nil if p[:x].nil? || p[:y].nil?

      Geom::Point3d.new(
        (p[:x] * DXF_UNIT_TO_MM).mm,
        (p[:y] * DXF_UNIT_TO_MM).mm,
        0
      )
    end.compact

    {
      points: pts,
      closed: entity.closed,
      label: entity.block_name || entity.layer.to_s,
    }
  end

  def report(dxf_path, grouped, built, skipped)
    lines = []
    lines << "壁セグメント数: #{grouped[:walls].size}"
    lines << "扉: #{grouped[:doors].size} / 窓: #{grouped[:windows].size}"
    lines << "家具: 生成 #{built} 件 / 除外・失敗 #{skipped.size} 件"

    unless skipped.empty?
      report_path = dxf_path.sub(/\.dxf\z/i, '') + '_skipped_furniture.txt'
      File.open(report_path, 'w:UTF-8') do |f|
        f.puts '以下の家具はベースモデルから除外されました(キッチン等の複雑形状、'
        f.puts 'または閉じたポリゴンとして読み取れなかったもの)。'
        f.puts '3D Warehouseの部品を配置するか、個別に採寸のうえ追加モデリングしてください。'
        f.puts ''
        skipped.each_with_index do |item, i|
          f.puts "#{i + 1}. label=#{item[:label]} reason=#{item[:reason] || 'excluded keyword match'}"
        end
      end
      lines << "除外家具リストを書き出しました: #{report_path}"
    end

    UI.messagebox(lines.join("\n"))
  end
end
