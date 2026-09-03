# frozen_string_literal: true

# 多言語対応(LANGS/TEXTS/t/EN_NUMBERS/stage_subtitle など)。

# ---- 多言語対応 --------------------------------------------------------
# 言語依存の文字列(画面と紙面に出るもの)は、すべてこの節の TEXTS に集める。
# コード中の他の場所には日本語・英語を直接書かない。
# ソースおよび生成される .typ 内のコメントは、利用者向けの出力ではないため
# 言語によらず日本語のままとする。
LANGS        = %i[ja en].freeze
DEFAULT_LANG = :ja
EN_FONT      = JP_FONT  # 英語のフォント(現時点では日本語と同じものを使う)
FONTS        = { ja: JP_FONT, en: EN_FONT }.freeze

# 実行時に選ばれている言語。--lang で書き換える(既定は DEFAULT_LANG)。
CURRENT_LANG = { lang: DEFAULT_LANG }

# 英語の数詞(0〜59)。時計(よみ)の解答を数字ではなく英単語で書くために使う。
EN_ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen
             fourteen fifteen sixteen seventeen eighteen nineteen].freeze
EN_TENS = %w[twenty thirty forty fifty].freeze
EN_NUMBERS = (0..59).map do |n|
  next EN_ONES[n] if n < 20

  tens = EN_TENS[n / 10 - 2]
  (n % 10).zero? ? tens : "#{tens}-#{EN_ONES[n % 10]}"
end.freeze

def lang = CURRENT_LANG[:lang]

def lang!(sym)
  CURRENT_LANG[:lang] = sym
end

# 本文・時計盤の数字に使うフォント。
def body_font = FONTS[lang]

# 言語依存の文字列を取り出す。%{...} を含むものは名前付き引数で埋める。
def t(key, **args)
  s = TEXTS.fetch(lang).fetch(key)
  args.empty? ? s : format(s, **args)
end

# 時計(よみ)の解答に出す数字。英語は数字ではなく英単語で書く(:numbers が有れば使う)。
def clock_num(n)
  words = TEXTS.fetch(lang)[:numbers]
  words ? words[n] : n.to_s
end

# 同じく「ふん」の数。1 桁のふんは英語では "oh" を付けて読む(例: three oh five)。
def clock_min_num(m)
  fmt = TEXTS.fetch(lang)[:clock_min_oh]
  s = clock_num(m)
  fmt && m < 10 ? format(fmt, m: s) : s
end

# ステージのサブタイトル(--stage-list の一覧と紙面の見出しに使う)。
def stage_subtitle(id)
  TEXTS.fetch(lang)[:subtitles][id.upcase]
end

TEXTS = {
  ja: {
    # --- 紙面(PDF)---
    title_mental: '暗算マスター',
    title_column: '筆算マスター',
    title_clock:  '時計マスター',
    name:         '名前',
    score:        '得点',
    answers:      '解答',
    ans_head_sep: ' ',   # 解答ページの見出しで大見出し・ステージ名・「解答」を区切る字
    set_no:       '第%{n}回',
    # 時計(よみ)の解答欄に出す字と、解答の文字列。
    # 「0 じ」は「12 じ」とも読めるため併記する。
    clock_hour_unit: 'じ',
    clock_min_unit:  'ふん',
    clock_h0:        '0 じ(12 じ)',  # 0 時の「じ」の部分
    clock_h:         '%{h} じ',      # 「じ」の部分(0 時以外)
    clock_only:      '%{h}',         # 「ふん」を問わないとき
    clock_hm:        '%{h} %{m} ふん',
    numbers:         nil,            # 数字はそのまま書く(英単語にしない)
    clock_min_oh:    nil,            # 1 桁のふんも数字をそのまま書く
    # --- ステージのサブタイトル ---
    subtitles: {
      'S1-1-1' => 'たしざん暗算1', 'S1-1-2' => 'たしざん暗算2', 'S1-1-3' => 'たしざん暗算3',
      'S1-1-4' => 'たしざん暗算4', 'S1-1-5' => 'たしざん暗算5',
      'S1-2-1' => 'ひきざん暗算1', 'S1-2-2' => 'ひきざん暗算2',
      'S1-3-1' => 'かけざん暗算1', 'S1-3-2' => 'かけざん暗算2', 'S1-3-3' => 'かけざん暗算3',
      'S1-3-4' => 'かけざん暗算4', 'S1-3-5' => 'かけざん暗算5', 'S1-3-6' => 'かけざん暗算6',
      'S1-5-1' => 'たしひき暗算1',
      'S1-8-1' => '小数かけざん暗算1',
      'S2-1-1' => 'たしざん筆算1', 'S2-1-2' => 'たしざん筆算2', 'S2-1-3' => 'たしざん筆算3',
      'S2-1-4' => 'たしざん筆算4', 'S2-1-5' => 'たしざん筆算5',
      'S2-2-1' => 'ひきざん筆算1', 'S2-2-2' => 'ひきざん筆算2', 'S2-2-3' => 'ひきざん筆算3',
      'S2-2-4' => 'ひきざん筆算4',
      'S3-1-1' => 'よみ1', 'S3-1-2' => 'よみ2', 'S3-1-3' => 'よみ3', 'S3-1-4' => 'よみ4'
    }.freeze,
    # --- 使い方(--help)---
    usage:          '使い方: ruby arithprac.rb [options]',
    opt_stage:      'ステージ名(例: S1-1-1)。--num/--pattern/--ratio を無視。',
    opt_pages:      "問題のページ数(1 ページ = 2 回分, 既定 #{DEFAULT_PAGES})",
    opt_stage_list: 'ステージ名とサブタイトルの一覧を表示して終了',
    opt_num:        "1 回あたりの問題数(暗算: #{MIN_PROBLEMS}〜#{MAX_PROBLEMS}, 既定 #{DEFAULT_PROBLEMS} / " \
                    "筆算・時計: #{REGION_SHAPES.keys.join('・')} のいずれか, 既定 #{DEFAULT_REGIONS}・" \
                    "#{DEFAULT_CLOCK_REGIONS})",
    opt_pattern:    'パターン名(例: P1-1-1)。複数指定可。--stage を無視。',
    opt_ratio:      'パターンの混合比率(--pattern と同数)。合計 1 に正規化。',
    opt_scale:      '文字・解答欄サイズ small/medium/large/onesmall(既定 small)。' \
                    'onesmall は暗算のみの 1 列レイアウト。時計では使わない。--stage 指定時は無視。',
    opt_output:     "出力ファイル名(.pdf)。不正な拡張子なら #{BASENAME}.pdf を使用。",
    opt_seed:       '乱数シード(再現用)',
    opt_lang:       "使用言語 #{LANGS.join('/')}(既定 #{DEFAULT_LANG})",
    opt_help:       'この使い方を表示',
    # --- 実行時のメッセージ ---
    seed_info:      'seed = %{seed}%{auto} で生成します。ページタグ: %{tag}',
    seed_auto:      '(自動生成)',
    info_kuku:      'ステージ %{key}(%{sub}): 九九固定 4 回・1 回 16 問(scale=%{scale}, CLI 指定は無視)。',
    info_stage:     'ステージ %{key}(%{sub}): %{pages} ページ・%{sets} 回・1 回 %{num} 問(%{desc})。',
    info_pattern:   'パターン %{list}: %{sets} 回・1 回 %{num} 問(%{desc})。',
    info_typ:       'Typst ファイルを生成: %{path}',
    info_pdf:       'PDF を生成: %{path}%{pages}',
    pages_suffix:   ' (全%{n}ページ)',
    warn_stage_opts:  '警告: --stage 指定時は --pattern/--ratio/--num は無視されます。',
    warn_stage_scale: '警告: --stage 指定時は --scale は無視されます(ステージ固有のスケールを使用)。',
    warn_clock_scale: '警告: 時計(P4-x-x)では --scale は使いません(時計盤はリージョンに合わせた大きさになります)。',
    warn_output_ext:  '警告: 出力拡張子が .pdf ではないため %{name} を使用します。',
    err_lang:         'エラー: --lang は %{list} のいずれかを指定してください(指定: %{v})。',
    err_pages:        'エラー: --pages は 1 以上を指定してください(指定: %{v})。',
    err_scale:        'エラー: --scale は %{list} のいずれかを指定してください(指定: %{v})。',
    err_scale_oneline: 'エラー: --scale %{scale}(1 列レイアウト)は暗算(P1-x-x/P3-x-x)のみで使用できます。',
    err_stage:        "エラー: ステージ '%{v}' は存在しません(一覧は --stage-list)。",
    err_pattern_unknown: 'エラー: パターンが存在しません: %{list}',
    err_pattern_forms:   'エラー: 暗算(P1-x-x/P3-x-x)・筆算(P2-x-x)・時計(P4-x-x)のパターンは同時に指定できません。',
    err_num_mental:   'エラー: 問題数は %{min}〜%{max} の範囲で指定してください(指定: %{v})。',
    err_num_region:   'エラー: 筆算・時計の問題数は %{shapes} のいずれかを指定してください(指定: %{v})。',
    err_ratio_count:  'エラー: --ratio は --pattern と同じ数だけ指定してください。',
    err_ratio_negative: 'エラー: --ratio に負の値は指定できません。',
    err_ratio_zero:   'エラー: --ratio の合計が 0 です。',
    err_no_mode:      'エラー: --stage または --pattern を指定してください(一覧は --stage-list)。',
    err_typst:        'typst のコンパイルに失敗しました。上の出力を確認してください。',
    err_stage_region: '内部エラー: ステージ %{key} の問題数(%{num})はリージョンに分割できません(%{shapes})。',
    err_dec_exp:      '内部エラー: 小数パターンの指数範囲 %{exps} が「1以上=%{ge1}」と矛盾します。',
    err_dec_empty:    '内部エラー: パターン %{key} を満たす数値の組がありません。'
  },
  en: {
    # --- 紙面(PDF)---
    title_mental: 'Mental Math Master',
    title_column: 'Written Calc Master',
    title_clock:  'Clock Master',
    name:         'Name',
    score:        'Pts',
    answers:      'Answers',
    ans_head_sep: ' - ', # 語の切れ目が分かるようにハイフンで区切る
    set_no:       'Set %{n}',
    # 時計(よみ)の解答は数字ではなく英単語で書く(例: 3 時 15 分 → three fifteen)。
    # 解答欄には「It is」(左)と「．」(右)を置き、単位は書かない。
    # 英語には「0 時」の読みが無いため、0 じ は 12 として書く(併記もしない)。
    clock_itis:      'It is',
    clock_period:    '．',
    clock_h0:        'twelve',       # 0 時の「じ」の部分
    clock_h:         '%{h}',         # 「じ」の部分(0 時以外)
    clock_only:      "%{h} o'clock", # 「ふん」を問わないとき
    clock_hm:        '%{h} %{m}',
    numbers:         EN_NUMBERS,     # 数字は英単語で書く
    clock_min_oh:    'oh %{m}',      # 1 桁のふん(例: 3 じ 5 ふん → three oh five)
    # --- ステージのサブタイトル ---
    # 紙面の見出し行に収める必要があるため、長くなりすぎないようにする。
    subtitles: {
      'S1-1-1' => 'Mental Add 1', 'S1-1-2' => 'Mental Add 2', 'S1-1-3' => 'Mental Add 3',
      'S1-1-4' => 'Mental Add 4', 'S1-1-5' => 'Mental Add 5',
      'S1-2-1' => 'Mental Sub 1', 'S1-2-2' => 'Mental Sub 2',
      'S1-3-1' => 'Mental Mul 1', 'S1-3-2' => 'Mental Mul 2', 'S1-3-3' => 'Mental Mul 3',
      'S1-3-4' => 'Mental Mul 4', 'S1-3-5' => 'Mental Mul 5', 'S1-3-6' => 'Mental Mul 6',
      'S1-5-1' => 'Mental Add & Sub 1',
      'S1-8-1' => 'Mental Decimal Mul 1',
      'S2-1-1' => 'Column Add 1', 'S2-1-2' => 'Column Add 2', 'S2-1-3' => 'Column Add 3',
      'S2-1-4' => 'Column Add 4', 'S2-1-5' => 'Column Add 5',
      'S2-2-1' => 'Column Sub 1', 'S2-2-2' => 'Column Sub 2', 'S2-2-3' => 'Column Sub 3',
      'S2-2-4' => 'Column Sub 4',
      'S3-1-1' => 'Clock Reading 1', 'S3-1-2' => 'Clock Reading 2',
      'S3-1-3' => 'Clock Reading 3', 'S3-1-4' => 'Clock Reading 4'
    }.freeze,
    # --- 使い方(--help)---
    usage:          'Usage: ruby arithprac.rb [options]',
    opt_stage:      'Stage name (e.g. S1-1-1). Ignores --num/--pattern/--ratio.',
    opt_pages:      "Pages of problems (1 page = 2 sets, default #{DEFAULT_PAGES})",
    opt_stage_list: 'List stage names with their subtitles and exit',
    opt_num:        "Problems per set (mental: #{MIN_PROBLEMS}-#{MAX_PROBLEMS}, default #{DEFAULT_PROBLEMS} / " \
                    "column and clock: one of #{REGION_SHAPES.keys.join(', ')}, default #{DEFAULT_REGIONS} and " \
                    "#{DEFAULT_CLOCK_REGIONS})",
    opt_pattern:    'Pattern name (e.g. P1-1-1). Repeatable. Ignores --stage.',
    opt_ratio:      'Mix ratio of the patterns (as many as --pattern). Normalized to sum 1.',
    opt_scale:      'Text and answer box size: small/medium/large/onesmall (default small). ' \
                    'onesmall is the one-column layout for mental only; not used for clock. Ignored with --stage.',
    opt_output:     "Output file name (.pdf). #{BASENAME}.pdf is used for any other extension.",
    opt_seed:       'Random seed (for reproducible output)',
    opt_lang:       "Language #{LANGS.join('/')} (default #{DEFAULT_LANG})",
    opt_help:       'Show this help',
    # --- 実行時のメッセージ ---
    seed_info:      'Generating with seed = %{seed}%{auto}. Page tag: %{tag}',
    seed_auto:      ' (auto-generated)',
    info_kuku:      'Stage %{key} (%{sub}): fixed times tables, 4 sets of 16 problems ' \
                    '(scale=%{scale}, CLI options ignored).',
    info_stage:     'Stage %{key} (%{sub}): %{pages} pages, %{sets} sets, %{num} problems per set (%{desc}).',
    info_pattern:   'Patterns %{list}: %{sets} sets, %{num} problems per set (%{desc}).',
    info_typ:       'Typst file written: %{path}',
    info_pdf:       'PDF written: %{path}%{pages}',
    pages_suffix:   ' (%{n} pages)',
    warn_stage_opts:  'Warning: --pattern/--ratio/--num are ignored when --stage is given.',
    warn_stage_scale: 'Warning: --scale is ignored when --stage is given (the scale of the stage is used).',
    warn_clock_scale: 'Warning: --scale is not used for clock patterns (P4-x-x); ' \
                      'the clock face is sized to fit its region.',
    warn_output_ext:  'Warning: the output extension is not .pdf, so %{name} is used.',
    err_lang:         'Error: --lang must be one of %{list} (given: %{v}).',
    err_pages:        'Error: --pages must be 1 or greater (given: %{v}).',
    err_scale:        'Error: --scale must be one of %{list} (given: %{v}).',
    err_scale_oneline: 'Error: --scale %{scale} (one-column layout) can be used only for mental patterns ' \
                       '(P1-x-x/P3-x-x).',
    err_stage:        "Error: stage '%{v}' does not exist (see --stage-list).",
    err_pattern_unknown: 'Error: no such pattern: %{list}',
    err_pattern_forms:   'Error: mental (P1-x-x/P3-x-x), column (P2-x-x) and clock (P4-x-x) patterns ' \
                         'cannot be given together.',
    err_num_mental:   'Error: the number of problems must be between %{min} and %{max} (given: %{v}).',
    err_num_region:   'Error: the number of problems for column and clock must be one of %{shapes} (given: %{v}).',
    err_ratio_count:  'Error: --ratio must be given as many times as --pattern.',
    err_ratio_negative: 'Error: --ratio must not be negative.',
    err_ratio_zero:   'Error: the sum of --ratio is 0.',
    err_no_mode:      'Error: give --stage or --pattern (see --stage-list).',
    err_typst:        'typst failed to compile. See the output above.',
    err_stage_region: 'Internal error: the number of problems of stage %{key} (%{num}) cannot be split ' \
                      'into regions (%{shapes}).',
    err_dec_exp:      'Internal error: exponent range %{exps} of the decimal pattern contradicts ' \
                      '"1 or greater = %{ge1}".',
    err_dec_empty:    'Internal error: no pair of numbers satisfies pattern %{key}.'
  }
}.freeze

