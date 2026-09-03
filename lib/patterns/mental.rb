# frozen_string_literal: true

# 暗算パターン(加算 P1-1 / 減算 P1-2 / 乗算 P1-3)。

# --- 暗算-加算(P1-1-x)---
def_pattern('P1-1-1', :add) { [rand(1..5), rand(1..5)] } # 和 2..10
def_pattern('P1-1-2', :add) do                            # 6..9 + 1..5, 和 7..10
  loop { a = rand(6..9); b = rand(1..5); break [a, b] if a + b <= 10 }
end
def_pattern('P1-1-3', :add) do                            # 1..9 + 1..9, 和 2..10(繰上がり無)
  loop { a = rand(1..9); b = rand(1..9); break [a, b] if a + b <= 10 }
end
def_pattern('P1-1-4', :add) do                            # 6..9 + 2..5, 和 11..14
  loop { a = rand(6..9); b = rand(2..5); break [a, b] if a + b >= 11 }
end
def_pattern('P1-1-5', :add) { [rand(6..9), rand(5..9)] }  # 和 11..18
def_pattern('P1-1-6', :add) do                            # 2..9 + 2..9, 和 11..18(繰上がり有)
  loop { a = rand(2..9); b = rand(2..9); break [a, b] if a + b >= 11 }
end

# --- 暗算-減算(P1-2-x)---
def_pattern('P1-2-1', :sub) do                            # 1..10 - 1..10, 差 0..9(a >= b)
  loop { a = rand(1..10); b = rand(1..10); break [a, b] if a >= b }
end
def_pattern('P1-2-2', :sub) do                            # 10..19 - 1..9, 差 1..10
  loop { a = rand(10..19); b = rand(1..9); break [a, b] if a - b <= 10 }
end

# --- 暗算-乗算(P1-3-x)---
def_pattern('P1-3-1', :mul) { [rand(2..9), rand(2..9)] }
def_pattern('P1-3-2', :mul) { [rand(11..99), rand(2..9)] }
def_pattern('P1-3-3', :mul) { [rand(11..19), rand(11..19)] }
def_pattern('P1-3-4', :mul) do
  # 22..99 × 12..19。0 は出現しない。被乗数(a)に '1' は出現しない。
  loop do
    a = rand(22..99); b = rand(12..19)
    break [a, b] if no_zero?(a) && no_zero?(b) && !a.to_s.include?('1')
  end
end
def_pattern('P1-3-5', :mul) do
  # 12..99 × 12..99。0 は出現しない。4 桁のうち '1' が過不足なく 1 回。
  loop do
    a = rand(12..99); b = rand(12..99)
    s = "#{a}#{b}"
    break [a, b] if !s.include?('0') && s.count('1') == 1
  end
end
def_pattern('P1-3-6', :mul) do
  # 22..99 × 22..99。0 および 1 は出現しない。
  loop do
    a = rand(22..99); b = rand(22..99)
    s = "#{a}#{b}"
    break [a, b] if !s.include?('0') && !s.include?('1')
  end
end

