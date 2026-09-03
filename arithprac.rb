# frozen_string_literal: true

# arithprac — 算数の計算問題・解答ジェネレータ
#
# 動作要件: Ruby 4.0 以降（標準ライブラリのみ）
# 出力     : Typst ファイル(.typ)を生成し、typst でコンパイルして PDF を得る
#
# 出題形式:
#   - 暗算(P1-x-x): 式を 1 行に並べ、右端の□に答えを書かせる。
#   - 筆算(P2-x-x): 1 回分の領域をリージョンに等分割し、1 問ずつ筆算の形で置く。
#   - 時計(P4-x-x): 同じくリージョンに等分割し、1 問ずつ時計盤と解答欄を置く。
#
# 生成物:
#   - 問題 : A4 横(landscape)を中央で 2 分割して A5×2。1 枚(A5)に 1 回分。
#            1 ページ = 2 回分。--pages で回数を制御(回数 = 2 * pages)。
#            中央に切り取り線を入れる。
#            暗算は左に前半・右に後半を並べる(奇数個なら左が 1 つ多い)。
#            筆算・時計は 1 回分を --num 個のリージョンに分けて行優先に並べる。
#   - 解答 : A4 縦。全回分をまとめて印刷(切らない)。「第N回」で対応付ける。
#
# 出題の指定:
#   --stage   : ステージ(パターンの混合比率と問題数のプリセット)
#   --pattern : パターン(単問の形式)を直接指定。--ratio で混合比率を指定。
#   いずれも指定が無い場合はエラー。

require 'optparse'

# 分割した各モジュールを依存順に読み込む(ロード時に評価される定数依存があるため順序が重要)。
require_relative 'lib/config'
require_relative 'lib/i18n'
require_relative 'lib/patterns/common'
require_relative 'lib/patterns/mental'
require_relative 'lib/patterns/decimal'
require_relative 'lib/patterns/column'
require_relative 'lib/patterns/clock'
require_relative 'lib/constraints'
require_relative 'lib/stages'
require_relative 'lib/generator'
require_relative 'lib/typst/common'
require_relative 'lib/typst/mental'
require_relative 'lib/typst/column'
require_relative 'lib/typst/clock'
require_relative 'lib/typst/answer'

# ---- メイン ------------------------------------------------------------

# ARGV から --lang の指定だけを先に読む。使い方(--help)やエラーの文言も
# --lang に従うため、OptionParser を組み立てる前に言語を確定させる必要がある。
# ここで拾えるのは完全な形の指定(--lang ja / --lang=ja)のみ。省略形は
# OptionParser が解釈するので、parse! の後にもう一度反映する。
def preparse_lang(argv)
  i = argv.index { |a| a == '--lang' || a.start_with?('--lang=') }
  return DEFAULT_LANG unless i

  to_lang(argv[i].start_with?('--lang=') ? argv[i].split('=', 2)[1] : argv[i + 1])
end

# 言語名(文字列)をシンボルにする。不正な値はエラーで終了する。
def to_lang(str)
  sym = str.to_s.downcase.to_sym
  abort t(:err_lang, list: LANGS.join('/'), v: str) unless LANGS.include?(sym)

  sym
end

main = lambda do
options = { pages: nil, num: nil, seed: nil,
            stage: nil, patterns: [], ratios: [], output: nil, stage_list: false,
            scale: nil, lang: nil }

lang!(preparse_lang(ARGV))

OptionParser.accept(Rational) do |s,|
  Rational(s)
rescue ArgumentError, ZeroDivisionError, TypeError
  raise OptionParser::InvalidArgument, s
end

parser = OptionParser.new do |o|
  o.banner = t(:usage)
  o.on('-s S', '--stage S', String, t(:opt_stage)) { |v| options[:stage] = v }
  o.on('-p P', '--pages P', Integer, t(:opt_pages)) { |v| options[:pages] = v }
  o.on('--stage-list', t(:opt_stage_list)) { options[:stage_list] = true }
  o.on('-n N', '--num N', Integer, t(:opt_num)) { |v| options[:num] = v }
  o.on('--pattern P', String, t(:opt_pattern)) { |v| options[:patterns] << v }
  o.on('--ratio R', Rational, t(:opt_ratio)) { |v| options[:ratios] << v }
  o.on('--scale S', String, t(:opt_scale)) { |v| options[:scale] = v }
  o.on('-o O', '--output O', String, t(:opt_output)) { |v| options[:output] = v }
  o.on('--lang L', String, t(:opt_lang)) { |v| options[:lang] = v }
  o.on('--seed S', Integer, t(:opt_seed)) { |v| options[:seed] = v }
  o.on('-h', '--help', t(:opt_help)) { puts o; exit }
end
parser.parse!(ARGV)

# 省略形(--lan など)で指定された場合はここで反映する(preparse_lang は完全形のみ)。
lang!(to_lang(options[:lang])) if options[:lang]

# --stage-list: 一覧表示して終了
if options[:stage_list]
  STAGES.each_key { |id| puts "#{id}\t#{stage_subtitle(id)}" }
  exit
end

# seed は未指定でも必ず確定させる(印刷後の対応づけと再現のため)。
# 完全な seed はログにのみ出力し、紙面には下位 16bit を 16 進 4 文字で入れる。
seed = options[:seed] || Random.new_seed
srand(seed)
tag = format('%04X', seed & 0xFFFF)
puts t(:seed_info, seed: seed, auto: options[:seed] ? '' : t(:seed_auto), tag: tag)

pages = options[:pages] || DEFAULT_PAGES
abort t(:err_pages, v: pages) if pages < 1
sets_count = 2 * pages

# --scale の検証(指定された場合のみ)。実際に採用するスケールはモード決定時に確定。
scale_opt = nil
if options[:scale]
  scale_opt = options[:scale].downcase.to_sym
  abort t(:err_scale, list: SCALES.keys.join('/'), v: options[:scale]) unless SCALES.key?(scale_opt)
end

# 出題モードの決定: --stage 優先、無ければ --pattern、いずれも無ければエラー。
stage_name = nil  # ステージ指定時のみサブタイトルを「第N回」の左に表示する
scale = DEFAULT_SCALE
form = :mental    # 出題形式(:mental=暗算 / :column=筆算)

if options[:stage]
  key = options[:stage].upcase
  stage = STAGES[key]
  abort t(:err_stage, v: options[:stage]) unless stage
  warn t(:warn_stage_opts) if !options[:patterns].empty? || !options[:ratios].empty? || options[:num]
  warn t(:warn_stage_scale) if scale_opt
  stage_name = stage_subtitle(key)
  scale = stage[:scale] # ステージ指定時は --scale を無視しステージ固有スケールを使う
  form = stage_form(stage)

  if stage[:special] == :kuku
    # 九九: 問題数・並び順・回数(4)が固定。--pages も無視。
    sets = make_kuku_sets
    num = 16
    puts t(:info_kuku, key: key, sub: stage_name, scale: scale)
  else
    num = stage_num(stage)
    # 筆算・時計は問題数 = リージョン数。分割できない問題数のステージは定義ミス。
    if form != :mental && !REGION_SHAPES.key?(num)
      abort t(:err_stage_region, key: key, num: num, shapes: REGION_SHAPES.keys.join(' / '))
    end
    # 履歴は全回で共有する(回をまたいだ重複回避のため)。
    hist = new_history(variety: form == :column)
    sets = Array.new(sets_count) { make_stage_set(stage, hist) }
    puts t(:info_stage, key: key, sub: stage_name, pages: pages, sets: sets_count,
                        num: num, desc: form_desc(form, scale))
  end

elsif !options[:patterns].empty?
  patterns = options[:patterns]
  unknown = patterns.reject { |p| PATTERNS.key?(p.upcase) }
  abort t(:err_pattern_unknown, list: unknown.join(', ')) unless unknown.empty?

  forms = patterns.map { |p| pattern_form(p) }.uniq
  abort t(:err_pattern_forms) if forms.size > 1
  form = forms.first

  if form == :mental
    num = options[:num] || DEFAULT_PROBLEMS
    unless (MIN_PROBLEMS..MAX_PROBLEMS).include?(num)
      abort t(:err_num_mental, min: MIN_PROBLEMS, max: MAX_PROBLEMS, v: num)
    end
  else
    # 筆算・時計: 問題数がリージョン分割形を決めるため、分割できる値のみ受け付ける。
    num = options[:num] || (form == :clock ? DEFAULT_CLOCK_REGIONS : DEFAULT_REGIONS)
    unless REGION_SHAPES.key?(num)
      abort t(:err_num_region, shapes: REGION_SHAPES.keys.join(' / '), v: num)
    end
  end

  ratios = options[:ratios]
  if ratios.empty?
    ratios = Array.new(patterns.size, Rational(1, patterns.size))
  else
    abort t(:err_ratio_count) unless ratios.size == patterns.size
    abort t(:err_ratio_negative) if ratios.any?(&:negative?)
    total = ratios.sum(0r)
    abort t(:err_ratio_zero) if total.zero?
    ratios = ratios.map { |r| r / total }
  end

  scale = scale_opt || DEFAULT_SCALE
  abort t(:err_scale_oneline, scale: scale) if form != :mental && oneline?(scale)
  warn t(:warn_clock_scale) if form == :clock && scale_opt

  hist = new_history(variety: form == :column)
  sets = Array.new(sets_count) { make_pattern_set(patterns, ratios, num, hist) }
  puts t(:info_pattern, list: patterns.join(', '), sets: sets_count, num: num,
                        desc: form_desc(form, scale))

else
  warn t(:err_no_mode)
  warn parser.help
  exit 1
end

# 出力先の決定
pdf_path = if options[:output]&.downcase&.end_with?('.pdf')
             options[:output]
           else
             warn t(:warn_output_ext, name: "#{BASENAME}.pdf") if options[:output]
             "#{BASENAME}.pdf"
           end
typ_path = pdf_path.sub(/\.pdf\z/i, '.typ')

# 大見出しは出題形式で決まる。
title_text = { column: t(:title_column), clock: t(:title_clock) }.fetch(form, t(:title_mental))

File.write(typ_path, build_typst(sets, num, title_text, stage_name, scale, form, tag))
puts t(:info_typ, path: typ_path)

if system('typst', 'compile', typ_path, pdf_path)
  pages_out = begin
    `pdfinfo #{pdf_path} 2>/dev/null`[/Pages:\s*(\d+)/, 1]
  rescue StandardError
    nil
  end
  puts t(:info_pdf, path: pdf_path, pages: pages_out ? t(:pages_suffix, n: pages_out) : '')
else
  warn t(:err_typst)
  exit 1
end
end

main.call if __FILE__ == $PROGRAM_NAME
