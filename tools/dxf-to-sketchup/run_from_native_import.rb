# run_from_native_import.rb
#
# 推奨ワークフロー(円弧・スプラインを含む複雑なDXFでも確実):
#   1. SketchUpで [ファイル] > [インポート] からDXFを直接読み込む
#      (レイヤーはSketchUpの「タグ」としてWalls/Doors/Windows/Furnitureの
#       名前のまま取り込まれる。単位はインポート時のダイアログで正しく指定すること)
#   2. RubyコンソールでこのスクリプトをloadしてRunFromNativeImport.runを実行
#
# 実行方法:
#   dir = 'このフォルダへの絶対パス'
#   load File.join(dir, 'floorplan_builder.rb')
#   load File.join(dir, 'run_from_native_import.rb')
#   RunFromNativeImport.run
#
# このスクリプトはインポート済みのジオメトリ(エッジ/フェイス)をタグ名で
# 分類し、floorplan_builder.rb の共通ロジック(壁union・開口カット・
# 家具押し出し)に渡す。dxf_parser.rbには依存しないので、円弧・曲線を含む
# 図面でも(SketchUpの純正インポーターが変換してくれる限り)扱える。
#
# ★注意: インポートされたエッジは通常「線分の集合」であり、閉じたポリゴンの
#   面が自動生成されない場合がある。家具の外形やoutline方式の壁については、
#   インポート後に対象タグのジオメトリを選択して右クリック→「面を作成」
#   ([Create Face] / エッジが平面で閉じていれば自動生成されることも多い)
#   を試すか、下記 edges_to_polygon で近似結合を行う。
module RunFromNativeImport
  LAYER_MATCHERS = {
    walls: /wall/i,
    doors: /door/i,
    windows: /window/i,
    furniture: /furniture/i,
  }.freeze

  module_function

  def run
    model = Sketchup.active_model
    grouped = { walls: [], doors: [], windows: [], furniture: [] }

    each_entity_recursive(model.entities) do |entity, transform|
      tag = entity.respond_to?(:layer) ? entity.layer : nil
      next unless tag

      category = LAYER_MATCHERS.find { |_k, re| tag.name =~ re }&.first
      next unless category

      case entity
      when Sketchup::Edge
        p1 = entity.start.position.transform(transform)
        p2 = entity.end.position.transform(transform)
        grouped[category] << { points: [p1, p2], closed: false, label: tag.name }
      when Sketchup::Face
        pts = entity.outer_loop.vertices.map { |v| v.position.transform(transform) }
        grouped[category] << { points: pts, closed: true, label: entity.material&.display_name.to_s }
      when Sketchup::ComponentInstance, Sketchup::Group
        # INSERT相当(家具ブロックなど)。挿入点のみ拾い、外形はブロック内の
        # ジオメトリから別途 bounds を使って矩形近似する。
        bounds = entity.definition.bounds
        pts = rectangle_from_bounds(bounds, entity.transformation * transform)
        name = entity.respond_to?(:definition) ? entity.definition.name : entity.name
        grouped[category] << { points: pts, closed: true, label: name.to_s }
      end
    end

    grouped[:walls] = merge_collinear_chains(grouped[:walls])

    model.start_operation('Floorplan 3D Generation (from native import)', true)

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

    UI.messagebox(
      "壁セグメント数: #{grouped[:walls].size}\n" \
      "扉: #{grouped[:doors].size} / 窓: #{grouped[:windows].size}\n" \
      "家具: 生成 #{built} 件 / 除外・失敗 #{skipped.size} 件\n" \
      "(除外家具の詳細はRubyコンソールの警告ログを参照)"
    )
    skipped.each { |item| puts "skipped furniture: #{item[:label]} (#{item[:reason] || 'excluded keyword'})" }
  end

  def each_entity_recursive(entities, transform = Geom::Transformation.new, &block)
    entities.each do |entity|
      case entity
      when Sketchup::Group
        yield entity, transform
        each_entity_recursive(entity.entities, entity.transformation * transform, &block)
      when Sketchup::ComponentInstance
        yield entity, transform
        # コンポーネント内部は展開しない(家具は挿入点+外形の矩形近似で十分なため)
      else
        yield entity, transform
      end
    end
  end

  def rectangle_from_bounds(bounds, transform)
    min = bounds.min
    max = bounds.max
    z = min.z
    [
      Geom::Point3d.new(min.x, min.y, z).transform(transform),
      Geom::Point3d.new(max.x, min.y, z).transform(transform),
      Geom::Point3d.new(max.x, max.y, z).transform(transform),
      Geom::Point3d.new(min.x, max.y, z).transform(transform),
    ]
  end

  # インポート直後のWallsタグは短い線分の集まりになっていることが多いため、
  # 端点が一致する線分同士を1本のポリラインに結合しておく
  # (build_wallsはeach_consでセグメント単位に処理するため必須ではないが、
  #  厚みの引き継ぎなど後続処理の精度を上げるために結合しておく)。
  def merge_collinear_chains(wall_entries)
    segments = wall_entries.map { |w| w[:points] }.select { |pts| pts.length == 2 }
    return wall_entries if segments.empty?

    chains = []
    used = Array.new(segments.length, false)

    segments.each_index do |i|
      next if used[i]

      used[i] = true
      chain = [segments[i][0], segments[i][1]]
      extended = true
      while extended
        extended = false
        segments.each_index do |j|
          next if used[j]

          p1, p2 = segments[j]
          if chain.last.distance(p1) < 0.001
            chain << p2
            used[j] = true
            extended = true
          elsif chain.last.distance(p2) < 0.001
            chain << p1
            used[j] = true
            extended = true
          end
        end
      end
      chains << { points: chain, closed: false, label: 'Walls' }
    end
    chains
  end
end
