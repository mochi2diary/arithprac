# frozen_string_literal: true

# パターン定義の基盤(def_pattern/PATTERNS/pattern_form ほか)。各 patterns/* より先に読む。

# ---- パターン定義 ------------------------------------------------------
# 各パターンは op(:add/:sub/:mul/:read)と、[a, b] を返す生成 proc を持つ。
# 制約(桁範囲・繰り上がり・0/1 の出現など)は棄却サンプリングで満たす。
# form は出題形式。P1-x-x/P3-x-x は暗算(:mental)、P2-x-x は筆算(:column)、
# P4-x-x は時計(:clock)。
PATTERNS = {}

# attrs はパターン固有の属性(時計の minute など)。問題の生成時に参照する。
def def_pattern(id, op, **attrs, &gen)
  form = case id.upcase
         when /\AP2/ then :column  # 筆算
         when /\AP4/ then :clock   # 時計
         else :mental              # 暗算
         end
  PATTERNS[id.upcase] = { id: id, op: op, form: form, gen: gen }.merge(attrs)
end

# パターン ID の出題形式(:mental / :column)。
def pattern_form(pid)
  PATTERNS[pid.upcase][:form]
end

# 数字を全角にする。筆算の問題部分のみで使う(解答ページは半角のまま)。
def zen_digits(n)
  n.to_s.tr('0-9', '０-９')
end

def no_zero?(n)
  !n.to_s.include?('0')
end

