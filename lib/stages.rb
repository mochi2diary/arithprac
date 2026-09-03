# frozen_string_literal: true

# ステージ定義(STAGES / stage_num / stage_form)。constraints.rb の後に読む。

# ---- ステージ定義 ------------------------------------------------------
# サブタイトル(たしざん暗算1 など)は言語依存のため TEXTS 側に置く(stage_subtitle)。
# entries: [[パターン候補配列, 問題数], ...]。候補が複数なら等確率で 1 つ選ぶ。
# constraints: [[コスト関数, 上限], ...]。1 回内で総コストを上限以下に調整する。
# special: :kuku のステージは問題数・並び順・回数が固定(CLI 指定を無視)。
STAGES = {
  'S1-1-1' => { scale: :large, constraints: [[COST_ONES, 2]],
                entries: [[%w[P1-1-1], 10]] },
  'S1-1-2' => { scale: :large, constraints: [[COST_ONES, 1]],
                entries: [[%w[P1-1-1], 2], [%w[P1-1-2], 2], [%w[P1-1-3], 6]] },
  'S1-1-3' => { scale: :large, constraints: [[COST_ONES, 1]],
                entries: [[%w[P1-1-1 P1-1-2 P1-1-3], 2], [%w[P1-1-4], 8]] },
  'S1-1-4' => { scale: :large,
                entries: [[%w[P1-1-1 P1-1-2 P1-1-3], 2], [%w[P1-1-4], 3], [%w[P1-1-5], 5]] },
  'S1-1-5' => { scale: :large,
                entries: [[%w[P1-1-3], 2], [%w[P1-1-6], 8]] },
  'S1-2-1' => { scale: :large,
                constraints: [[COST_B_ONES, 1], [COST_A_TEN, 2], [COST_ZERO_ANS, 1]],
                entries: [[%w[P1-2-1], 10]] },
  'S1-2-2' => { scale: :large,
                constraints: [[COST_B_ONES, 1], [COST_ZERO_TEN_ANS, 1]],
                entries: [[%w[P1-2-1], 2], [%w[P1-2-2], 8]] },
  'S1-3-1' => { scale: :medium, special: :kuku },
  'S1-3-2' => { scale: :medium, entries: [[%w[P1-3-1], 16]] },
  'S1-3-3' => { scale: :small, entries: [[%w[P1-3-2], 20]] },
  'S1-3-4' => { scale: :small, entries: [[%w[P1-3-3], 20]] },
  'S1-3-5' => { scale: :small, entries: [[%w[P1-3-4], 20]] },
  'S1-3-6' => { scale: :small, entries: [[%w[P1-3-5], 10], [%w[P1-3-6], 10]] },
  'S1-5-1' => { scale: :large,
                constraints: [[COST_MIXED_ONES, 1], [COST_A_TEN, 1], [COST_SUB_ZERO_TEN_ANS, 1]],
                entries: [[%w[P1-1-3], 2], [%w[P1-1-6], 3],
                          [%w[P1-2-1], 2], [%w[P1-2-2], 3]] },
  'S1-8-1' => { scale: :onesmall,
                entries: [[dec_pats(1..5), 1], [dec_pats(6..10), 1], [dec_pats(11..15), 1],
                          [dec_pats(16..19), 1], [dec_pats(20..23), 1], [dec_pats(24..31), 1],
                          [dec_pats(32..39), 1], [dec_pats(40..51), 1], [dec_pats(52..63), 1],
                          [dec_pats(64..75), 1],
                          [dec_pats(17, 19, 22, 23, 26, 27, 30, 31, 34, 35, 38, 39), 5]] },
  'S2-1-1' => { scale: :large, constraints: CONSTR_A_TENS_ONE,
                entries: [[%w[P2-1-1], 12]] },
  'S2-1-2' => { scale: :large, constraints: CONSTR_A_TENS_ONE,
                entries: [[%w[P2-1-1], 4], [%w[P2-1-2], 8]] },
  'S2-1-3' => { scale: :large, constraints: CONSTR_A_TENS_ONE,
                entries: [[%w[P2-1-3], 4], [%w[P2-1-4], 8]] },
  'S2-1-4' => { scale: :large, constraints: CONSTR_A_TENS_ZERO_ONE,
                entries: [[%w[P2-1-4], 1], [%w[P2-1-5], 3], [%w[P2-1-6], 8]] },
  'S2-1-5' => { scale: :large, constraints: CONSTR_TENS_ZERO_ONE,
                entries: [[%w[P2-1-7], 1], [%w[P2-1-8], 5], [%w[P2-1-9], 6]] },
  'S2-2-1' => { scale: :large, constraints: CONSTR_SUB_UNITS,
                entries: [[%w[P2-2-1], 12]] },
  'S2-2-2' => { scale: :large, constraints: CONSTR_SUB_UNITS,
                entries: [[%w[P2-2-1], 4], [%w[P2-2-2], 8]] },
  'S2-2-3' => { scale: :large, constraints: CONSTR_SUB_LOW2,
                entries: [[%w[P2-2-2], 1], [%w[P2-2-3], 2], [%w[P2-2-4], 2],
                          [%w[P2-2-7], 3], [%w[P2-2-8], 4]] },
  'S2-2-4' => { scale: :large, constraints: CONSTR_SUB_LOW2,
                entries: [[%w[P2-2-3], 1], [%w[P2-2-4], 1], [%w[P2-2-5], 1], [%w[P2-2-6], 1],
                          [%w[P2-2-7], 1], [%w[P2-2-8], 2], [%w[P2-2-9], 2], [%w[P2-2-10], 2],
                          [%w[P2-2-11], 1]] },
  'S3-1-1' => { scale: :small,
                entries: [[%w[P4-1-1], 4]] },
  'S3-1-2' => { scale: :small, constraints: CONSTR_CLOCK,
                entries: [[%w[P4-1-1], 1], [%w[P4-1-2], 3]] },
  'S3-1-3' => { scale: :small, constraints: CONSTR_CLOCK,
                entries: [[%w[P4-1-2], 1], [%w[P4-1-3], 3]] },
  'S3-1-4' => { scale: :small, constraints: CONSTR_CLOCK,
                entries: [[%w[P4-1-1 P4-1-2 P4-1-3], 1], [%w[P4-1-4], 3]] }
}.freeze

def stage_num(stage)
  stage[:entries].sum { |_pats, count| count }
end

# ステージの出題形式(:mental / :column)。九九(entries 無し)は暗算。
def stage_form(stage)
  return :mental unless stage[:entries]

  pattern_form(stage[:entries].first[0].first)
end

