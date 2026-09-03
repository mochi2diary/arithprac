# frozen_string_literal: true

# 時計パターン(よみ P4-1)と def_clock_pattern / clock_answer。

# --- 時計-よみ(P4-1-x)---
# 時計(よみ)は a を「じ」(0..11)、b を「ふん」(0..59)として扱う。
# minute が偽のパターン(P4-1-1)は「ふん」を問わない(解答欄にも「ふん」を出さない)。

# パターンごとの「ふん」の候補。
CLOCK_MINUTES = {
  'P4-1-1' => [0],
  'P4-1-2' => [15, 30, 45],
  'P4-1-3' => [5, 10, 20, 25, 35, 40, 50, 55],
  'P4-1-4' => (1..59).reject { |m| (m % 5).zero? }.freeze
}.freeze

# 時計(よみ)のパターンを定義する。minute: 偽なら「ふん」を問わない。
def def_clock_pattern(id, minute: true)
  mins = CLOCK_MINUTES[id.upcase]
  def_pattern(id, :read, minute: minute) { [rand(12), mins.sample] }
end

def_clock_pattern('P4-1-1', minute: false)
def_clock_pattern('P4-1-2')
def_clock_pattern('P4-1-3')
def_clock_pattern('P4-1-4')

# 時計(よみ)の解答文字列。「じ」「ふん」の書き方と 0 時の扱いは言語ごとに異なる
# (日本語は「0 じ(12 じ)」と併記、英語は 12 とのみ書く)ため TEXTS 側で決める。
def clock_answer(hour, minute, minute_asked)
  h = hour.zero? ? t(:clock_h0) : t(:clock_h, h: clock_num(hour))
  minute_asked ? t(:clock_hm, h: h, m: clock_min_num(minute)) : t(:clock_only, h: h)
end

