# frozen_string_literal: true

# Typst 生成: 時計盤・時計解答欄のレイアウト定義。

def typ_clock_face_defs
  <<~TYP

    // --- 時計盤(モノクロ / 長針・短針)---
    #let clock(hour, minute, size: 6cm, ink: black) = {
      let r = size / 2   // 半径
      let cx = r         // 中心 x
      let cy = r         // 中心 y

      // 12 時方向を基準に、時計回り ang・中心からの距離 rad の点を返す
      let pt(ang, rad) = (cx + rad * calc.sin(ang), cy - rad * calc.cos(ang))

      box(width: size, height: size, {
        // 外周の円
        let sw = 0.03 * r
        place(dx: sw / 2, dy: sw / 2, circle(radius: r - sw / 2, stroke: sw + ink))

        // 目盛り(分 = 細・時 = 太)
        for i in range(60) {
          let ang = i * 6deg
          let is-hour = calc.rem(i, 5) == 0
          let len = if is-hour { 0.12 * r } else { 0.06 * r }
          let tw  = if is-hour { 0.03 * r } else { 0.015 * r }
          place(line(start: pt(ang, r - 0.05 * r), end: pt(ang, r - 0.05 * r - len),
                     stroke: tw + ink))
        }

        // 数字 1-12
        let nr = 0.67 * r     // 数字を置く円の半径
        let cell = 0.32 * r   // 数字用セルの一辺
        for n in range(1, 13) {
          let p = pt(n * 30deg, nr)
          place(dx: p.at(0) - cell / 2, dy: p.at(1) - cell / 2,
            box(width: cell, height: cell,
              align(center + horizon,
                text(font: "#{body_font}", size: 0.20 * r, fill: ink)[#n])))
        }

        // 針(学習用に、中心から先端までで尾は出さない)
        let hand(ang, len, tw) = place(line(start: (cx, cy), end: pt(ang, len),
          stroke: (paint: ink, thickness: tw, cap: "round")))
        let hm = calc.rem(hour, 12)
        hand((hm + minute / 60) * 30deg, 0.52 * r, 0.055 * r)  // 短針: 太く短い
        hand(minute * 6deg, 0.80 * r, 0.035 * r)               // 長針: 細く長い

        // 中心の軸
        let dot = 0.05 * r
        place(dx: cx - dot, dy: cy - dot, circle(radius: dot, fill: ink))
      })
    }
  TYP
end

# 解答欄(角丸四角)の中の字。置き方が言語で異なるため定義を分ける。
# 幅は時計盤(直径 d)より左右 ansboxover ずつ広く、高さは h。
def typ_clockans_def
  lang == :en ? typ_clockans_en : typ_clockans_ja
end

# 日本語: 単位「じ」「ふん」を置く。
# 「ふん」は右端が角丸の始まり(右端 - 半径)より fundx 右、「じ」は右端が
# 解答欄の中央より jidx 左に来るように置く。どちらも下端は解答欄の下端から unitgap 上。
# showmin が偽のパターン(「ふん」を問わない)は「ふん」を出さず、
# 「じ」を「ふん」の位置(角丸の始まり。fundx のずらしはしない)に置く。
def typ_clockans_ja
  c = CLOCK_LAYOUT
  <<~TYP.chomp
    #let fundx = #{c[:fun_dx]}mm  // 「ふん」の右端を角丸の始まりから右へずらす量
    #let jidx  = #{c[:ji_dx]}mm  // 「じ」の右端を解答欄の中央から左へずらす量

    #let clockans(d, h, showmin) = {
      let w = d + 2 * ansboxover
      // 文字の右端の位置。右揃えの箱の幅で表す。
      let jiw = if showmin { w / 2 - jidx } else { w - ansboxr }
      box(width: w, height: h, stroke: ansboxthk, radius: ansboxr, {
        place(bottom + left, dy: -unitgap,
          box(width: jiw, align(right)[#text(size: unitfs)[#{t(:clock_hour_unit)}]]))
        if showmin {
          place(bottom + left, dy: -unitgap,
            box(width: w - ansboxr + fundx, align(right)[#text(size: unitfs)[#{t(:clock_min_unit)}]]))
        }
      })
    }
  TYP
end

# 英語: 単位は書かず、「It is」(左)と「．」(右)のあいだに下線を 1 本引く。
# 解答は「three fifteen」のように英単語で書くため、「ふん」の有無で置き方を変えない。
# 枠(角丸四角)は描かないが、占める幅と高さは日本語と同じにする。文字の左右の位置も
# 日本語と同じ基準(角丸の終わり / 始まり)から測るため、ansboxr は位置の基準として残す。
# 「It is」は左端が角丸の終わり(直線の始まり)より itisdx 左、「．」は右端が
# 角丸の始まりより perioddx 右。どちらも下端は解答欄の下端から unitgap 上。
# 下線は文字と同じ下端の高さに、「It is」の右端と「．」の左端から linegap ずつ空けて引く。
# 全体(「It is」・下線・「．」)は、日本語の「じ」「ふん」の位置より enlift 上に置く。
def typ_clockans_en
  c = CLOCK_LAYOUT
  <<~TYP.chomp
    #let itisdx   = #{c[:itis_dx]}mm  // 「It is」の左端を角丸の終わりから左へずらす量
    #let perioddx = #{c[:period_dx]}mm  // 「．」の右端を角丸の始まりから右へずらす量
    #let periodfs = #{c[:period_fs]}pt  // 「．」の文字サイズ(全角。見やすさのため大きめ)
    #let linegap  = #{c[:line_gap]}mm  // 下線の両端と「It is」「．」のあいだの空き
    #let enlift   = #{c[:en_lift]}mm  // 「It is」・下線・「．」の全体を上へずらす量
    #let enbase   = unitgap + enlift  // 解答欄の下端から、字と下線の下端までの距離

    #let clockans(d, h, showmin) = {
      let w = d + 2 * ansboxover
      let itis = text(size: unitfs)[#{t(:clock_itis)}]
      let period = text(size: periodfs)[#{t(:clock_period)}]
      box(width: w, height: h, {
        place(bottom + left, dx: ansboxr - itisdx, dy: -enbase, itis)
        // 「．」の右端の位置は、右揃えの箱の幅で表す。
        place(bottom + left, dy: -enbase,
          box(width: w - ansboxr + perioddx, align(right)[#period]))
        // 記入欄の下線。両端は文字の幅を測って決める。
        context {
          let x1 = ansboxr - itisdx + measure(itis).width + linegap
          let x2 = w - ansboxr + perioddx - measure(period).width - linegap
          place(bottom + left, dx: x1, dy: -enbase, line(length: x2 - x1, stroke: ansboxthk))
        }
      })
    }
  TYP
end

# 問題(時計・よみ)の定義。1 リージョンに 時計盤(上)と解答欄(下)を置く。
# 時計盤の直径はリージョンに収まる最大値(上限 clockdiam)を Typst 側で決める
# (リージョンの大きさは --num と見出しの高さで変わるため)。
def typ_clock_defs
  c = CLOCK_LAYOUT
  <<~TYP

    // --- 寸法(時計・よみ) ---
    #let clockdiam = #{c[:diam]}mm    // 時計盤の直径(リージョンに入らなければ縮める)
    #let ansboxh   = #{c[:boxh]}mm    // 解答欄の高さ
    #let ansboxover = #{c[:boxover]}mm  // 解答欄が時計盤からはみ出す幅(左右それぞれ)
    #let ansboxr   = #{c[:boxr]}mm     // 解答欄の角丸の半径
    #let ansboxthk = #{c[:boxthk]}pt   // 解答欄の線の太さ
    #let clockgap  = #{c[:gap]}mm     // 時計盤と解答欄のあいだの空き
    #let unitfs    = #{c[:unitfs]}pt   // 解答欄の中の字(「じ」「ふん」/「It is」)の文字サイズ
    #let unitgap   = #{c[:unitgap]}mm     // 解答欄の下端から中の字の下端までの距離
    #let rpadx     = #{c[:rpad_x]}mm     // リージョン内の左右の余白
    #let rpady     = #{c[:rpad_y]}mm     // 同・上下の余白
    #let numfs     = 12pt   // 問題番号(丸数字)のフォントサイズ

    #{typ_clockans_def}

    // 1 リージョン(1 問分)。時計盤は上、解答欄は下、どちらも左右中央に置く。
    // 番号は左上(place なので配置に影響しない。時計盤は丸いので重ならない)。
    // 大きさは layout でリージョンの実寸を測って決める。時計盤は clockdiam を
    // 上限にリージョンいっぱいまで大きくし、解答欄の高さは ansboxh を上限に
    // 時計盤の直径以下に抑える(リージョンが小さいときに解答欄だけが残らないように)。
    #let region(it) = block(width: 100%, height: 100%, inset: (x: rpadx, y: rpady), {
      place(top + left, text(size: numfs)[#it.n])
      layout(sz => {
        let avail = sz.height - clockgap   // 時計盤と解答欄で分け合う高さ
        // 解答欄が ansboxh に届かない(= 直径と同じ高さになる)なら avail の半分。
        let dmax = if avail / 2 <= ansboxh { avail / 2 } else { avail - ansboxh }
        // 幅は解答欄(直径 + 左右のはみ出し)がリージョンに収まる範囲まで。
        let d = calc.min(clockdiam, sz.width - 2 * ansboxover, dmax)
        grid(columns: (100%), rows: (auto, 1fr, auto), align: center,
          stroke: none, inset: 0pt,
          clock(it.h, it.m, size: d), [], clockans(d, calc.min(ansboxh, d), it.showmin))
      })
    })
  TYP
end

# リージョン割り(筆算・時計で共通)。見出し以降の残り領域を num 個のリージョンに
# 等分割し、1 リージョンに 1 問を置く。1 問の中身は呼び出し側が region で定義する。
