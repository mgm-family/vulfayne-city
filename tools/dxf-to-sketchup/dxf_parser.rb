# dxf_parser.rb
#
# 最小限のASCII DXFパーサー。外部gemやSketchUpのAPIに依存しないプレーンな
# Rubyコードなので、SketchUpのRubyコンソール以外(手元のRuby)でも動作確認できる。
#
# 対応エンティティ: LINE, LWPOLYLINE, POLYLINE(+VERTEX/SEQEND), INSERT, CIRCLE
# 非対応: ARC, SPLINE, ELLIPSE, バイナリDXF, ブロック定義の再帰展開
#
# 壁・建具レイヤーに円弧やスプラインが含まれる図面は、CAD側で事前に
# 直線・ポリラインへ変換(分解/エクスプロード)してから読み込むこと。
# 対応が難しい場合は run_from_native_import.rb (SketchUp純正DXFインポート
# を使う方式)を利用したほうが確実。
module DxfParser
  Entity = Struct.new(
    :type,        # 'LINE' | 'LWPOLYLINE' | 'POLYLINE' | 'INSERT' | 'CIRCLE'
    :layer,       # レイヤー名(文字列)
    :points,      # [{x:, y:}, ...] 図面単位の生座標
    :closed,      # LWPOLYLINE/POLYLINEが閉じているか
    :block_name,  # INSERTのブロック名
    :radius,      # CIRCLEの半径
    keyword_init: true
  )

  SUPPORTED_TYPES = %w[LINE LWPOLYLINE POLYLINE INSERT CIRCLE].freeze

  def self.parse(path)
    pairs = read_pairs(path)
    entities = []
    i = 0
    while i < pairs.length
      code, value = pairs[i]
      if code == 0 && SUPPORTED_TYPES.include?(value)
        i, entity = parse_entity(pairs, i, value)
        entities << entity if entity && entity.layer
      else
        i += 1
      end
    end
    entities
  end

  def self.read_pairs(path)
    lines = File.readlines(path, chomp: true)
    pairs = []
    idx = 0
    while idx + 1 < lines.length
      code = lines[idx].to_s.strip.to_i
      value = lines[idx + 1].to_s.strip
      pairs << [code, value]
      idx += 2
    end
    pairs
  end
  private_class_method :read_pairs

  def self.parse_entity(pairs, start_i, type)
    i = start_i + 1
    layer = nil
    points = []
    closed = false
    block_name = nil
    radius = nil
    line_start = {}
    line_end = {}

    while i < pairs.length
      code, value = pairs[i]
      break if code == 0 # 次のエンティティに到達

      case type
      when 'LINE'
        case code
        when 8  then layer = value
        when 10 then line_start[:x] = value.to_f
        when 20 then line_start[:y] = value.to_f
        when 11 then line_end[:x] = value.to_f
        when 21 then line_end[:y] = value.to_f
        end
      when 'LWPOLYLINE'
        case code
        when 8  then layer = value
        when 70 then closed = (value.to_i & 1) == 1
        when 10 then points << { x: value.to_f, y: 0.0 }
        when 20 then points.last[:y] = value.to_f if points.last
        end
      when 'POLYLINE'
        layer = value if code == 8
        closed = (value.to_i & 1) == 1 if code == 70
        # 頂点(VERTEX)は下のループで別途消費する
      when 'INSERT'
        case code
        when 8  then layer = value
        when 2  then block_name = value
        when 10 then points << { x: value.to_f, y: 0.0 }
        when 20 then points.last[:y] = value.to_f if points.last
        end
      when 'CIRCLE'
        case code
        when 8  then layer = value
        when 10 then points << { x: value.to_f, y: 0.0 }
        when 20 then points.last[:y] = value.to_f if points.last
        when 40 then radius = value.to_f
        end
      end
      i += 1
    end

    if type == 'LINE'
      points = [line_start, line_end] if line_start[:x] && line_end[:x]
    end

    if type == 'POLYLINE'
      i, verts = consume_polyline_vertices(pairs, i)
      points = verts
    end

    return [i, nil] if layer.nil?

    entity = Entity.new(
      type: type, layer: layer, points: points, closed: closed,
      block_name: block_name, radius: radius
    )
    [i, entity]
  end
  private_class_method :parse_entity

  # POLYLINE本体の後に続く VERTEX ... SEQEND の並びを読み取る
  def self.consume_polyline_vertices(pairs, i)
    verts = []
    while i < pairs.length
      code, value = pairs[i]
      if code == 0 && value == 'VERTEX'
        i += 1
        vx = vy = nil
        while i < pairs.length && pairs[i][0] != 0
          vc, vv = pairs[i]
          vx = vv.to_f if vc == 10
          vy = vv.to_f if vc == 20
          i += 1
        end
        verts << { x: vx, y: vy } if vx && vy
      elsif code == 0 && value == 'SEQEND'
        i += 1
        break
      else
        break
      end
    end
    [i, verts]
  end
  private_class_method :consume_polyline_vertices
end
