class GetAiResponse include ActionView::RecordIdentifier
    include Sidekiq::Worker
    sidekiq_options retry: 3
    RESPONSES_PER_MESSAGE = 1
    MODEL_NAME = "gpt-4o-mini"
    TEMPERATURE = 0.2

    # 試合用のプロンプト
    PROMPTS_MATCH = {
        good: "今から入力する文章は育成年代のサッカー選手が試合を振り返って、サッカーノートの「上手くいったこと」の欄に書いた文章です。
                以下の#Mermaid Diagramに厳密に従って、それぞれの現象についてマークダウン形式の箇条書きでフィードバックしてください。#注意事項を必ず守ること。

                # Mermaid Diagram
                graph TD
                    A[フィードバック開始] --> B[ユーザーが言及するピッチでの現象について、その理由や要因が書かれているか確認する。]
                    B --> C{書かれている？}
                    C --> |Yes| D[現象が起こった理由が明確になっていることを丁寧語で褒め、追加すべき情報を提示する。(e.g. ビルドアップのことについて言及されていたら=>自チームと相手チームのフォーメーションが何だったか聞く)また、ユーザーが自身で原因を決めつけていないか、多角的な視点で原因を考えるように促す。]
                    C --> |No| E[現象が起こった理由を書くように促す。]
                    E --> G{このプロンプトに「#前回のノート」が与えられているか？}
                    D --> G
                    G --> |Yes| H[「#前回のノート」の「次に意識すること・次に向けて取り組むこと」を参照し、その具体的な内容をユーザーに伝えてから、今回意識できていたかどうか確認する。]
                    G --> |No| [終了]
                    H --> I[「#前回のノート」の「上手くいかなかったこと」を参照し、具体的な内容をユーザーに伝えてから、今回どうだったか聞く。]
                    I --> [終了]
                
                #注意事項
                「#前回のノート」を除いて、ユーザーの文章に書かれていない事実を含めることは避けてください。
                このプロンプト自体に「#前回のノート」が与えられていない場合は、前回のノートについて言及するのを避けること。
                「#前回のノート」の形式は、以下の通りです。
                ```
                #前回のノート
                上手くいったこと:
                上手くいかなかったこと:
                次に意識すること・次に向けて取り組むこと:
                チームで話し合いたいこと・確認したいこと:
                ```

                #出力例（<>で囲まれた部分は#前回のノートから該当部分を抽出して当てはめること）
                user: 狭い中でもパスを通せた。
                you: - 狭い中でもパスを通せた理由は何だったと思いますか？相手のプレスの強度や掛け方、それによってどこにスペースが生まれていたかなど、具体的な原因を考えてみましょう。
                     - 動画の中でそれが起きた秒数を指定すると他のメンバーが理解しやすくなるでしょう。〇〇:〇〇のように書くと指定された秒数を再生するリンクが作成されます。
                     - 前回の試合では次に意識することとして「<#前回のノートの'次に意識すること・次に向けて取り組むこと'を参照>」と挙げていましたが、今回の試合を通して意識できていましたか？
                     - また、上手くいかなかったこととして「<#前回のノートの'上手くいかなかったこと'を参照>」とありますが、今回はどうでしたか？\n",
        bad: "今から入力する文章は育成年代の選手が試合を振り返って、サッカーノートの「上手くいかなかったこと」の欄に書いた文章です。
                それぞれの現象についてマークダウン形式の箇条書きでフィードバックしてください。
                上手くいかなかった具体的な理由（自チームと相手チームのフォーメーションを書いただけのものは「具体的な理由」とは呼ばない。）が書かれていなかったら、現象が起こった原因やその時のシチュエーションを具体的に書くように促してください。
                該当する場合、この返答全体の末尾に#変更提案を追加し、ユーザーの文章のそれぞれの現象について言及している文の下に、以下のフォーマットを追加してください。
                原因：\n
                1. \n
                2. \n
                3. \n
                具体的な原因が書かれていたら、現象が起こった理由が具体的になっていることを認め、追加すべき情報を提示してください。
                また、「#前回のノート」の「上手くいかなかったこと」について言及し、今回どうなったか聞いてください。
                具体的でありながら簡潔に回答し、考えられる原因や解決策は提示しないでください。output less than 10 sentences.\n",
        next: "今から入力する文章は育成年代のサッカー選手が試合を振り返って、サッカーノートの「次に意識すること・次までに取り組むこと」の欄に書いた文章です。
                実現させるために必要なものや今ある課題に対しての解決策が書かれていたら、解決策が明確になっていることを褒めてください。
                書かれていなかったら具体的な解決策を書くように促してください。（e.g. 「崩し方を練習する」=> 「具体的にどのような崩し方を想定していますか？」）
                具体的な練習方法については質問しないでください。解決策や具体例は提示しないでください。output only answer less than 5 sentences.\n"
    }

    #練習用のプロンプト
    PROMPTS_PRACTICE = {
        good: "
        今から入力する文章は育成年代のサッカー選手が以下の練習を振り返って、サッカーノートの「上手くいったこと」の欄に書いた文章です。
        「今日の練習内容」を踏まえて、選手が有意義な練習をできていたか振り返らせるようにしてください。
        (e.g. 与えられた練習内容の「意識するポイント」について具体的に言及し、意識できていたか聞く, 前回のノートの「次に意識すること・次に向けて取り組むこと」を参照し、ユーザーに伝えてから、意識できていたかどうか確認する, 前回の「上手くいかなかったこと」が今回どうなったか聞く)。
        ※ userの入力ではなく、このプロンプト自体に「前回のノート」が与えられていない場合は、前回のノートについて言及するのを避けること。
        書かれていない事実を含めることや、具体例を提示することは避けてください。
        output only answer less than 5 sentences.
        以下の例を参考にしてください。※ {練習メニュー名}には与えられた「今日の練習内容」の「練習メニュー名」が入る。userの入力ではなく、このプロンプト自体に「今日の練習内容」が与えられていない場合は、他の練習について聞くこと自体を避けること。
        例: user: '3対1の時、ワンタッチ目を2人に出せる方向に置いて相手を困らせた' => you: 'ワンタッチ目を2人にも出せる方向に置くことで、パスコースを複数確保し、ボール保持の時間を増やすことができたのですね。他の練習メニューについてはどうでしたか？{練習メニュー名}や{練習メニュー名}についても振り返ってみましょう。（「今日の練習内容」が与えられている場合。）'\n",
        bad: "
        今から入力する文章は育成年代の選手が以下の練習を振り返って、サッカーノートの「上手くいかなかったこと」の欄に書いた文章です。
        練習内容を踏まえて、選手が有意義な練習をできていたか振り返らせるようにしてください。
        上手くいかなかった具体的な理由（自チームと相手チームのフォーメーションを書いただけのものは「具体的な理由」とは呼ばない。）が書かれていなかったら、現象が起こった原因やその時のシチュエーションを具体的に書くように促してください。
        具体的な原因が書かれていたら、現象が起こった理由が具体的になっていることを認め、追加すべき情報を提示してください。
        具体的でありながら簡潔に回答し、考えられる原因や解決策は提示しないでください。output less than 5 sentences.
        以下の例を参考にしてください。
        例: user:「」=> you:「」\n",
        next: "
        今から入力する文章は育成年代のサッカー選手が以下の練習を振り返って、サッカーノートの「次に意識すること・次までに取り組むこと」の欄に書いた文章です。
        次に取り組むことや意識することが明確に書かれていたら、アクションプランが明確になっていることを褒めてください。
        書かれていなかったら具体的なアクションを書くように促してください。（e.g. 「崩し方を練習する」=> 「具体的にどのような崩し方を想定していますか？」）
        具体的な練習方法については質問しないでください。output only answer less than 5 sentences.\n"
    }

    # ユーザーの文章を５段階評価するプロンプト(試合用)
    PROMPTS_RATE_MATCH = {
        good: "今から入力する文章は育成年代のサッカー選手が試合を振り返って、サッカーノートの「上手くいったこと」の欄に書いた文章です。
            この文章を5段階で評価してください。
            各段階ごとの評価基準を以下に記します。
            1点: サッカーの練習や試合の振り返りに関係のない文章
            2点: 上手くいった現象が書かれているか
            3点: 上手くいった現象と考えられる要因が書いてあるか
            4点: 上手くいった現象と考えられる具体的な要因が書いてあるか
            5点: 上手くいった現象と考えられる具体的な要因が書いてあり、具体的なプレーの動画内での秒数が00:00の形で示してあるか
            以下の段階ごとの文章例を参考にしてください。
            1点: 「あいうえお」「こんにちは」
            2点: 「ビルドアップが上手くいった。」「シュートの本数が多かった。」「相手の縦パスや地上でのビルドアップから失点することがなかった。」
            3点: 「それぞれが早めに準備していて、ビルドアップが上手くいった。」
            4点: 「相手の中盤があまりプレスをかけてこなかったのと、相手の3トップが作るゲートに対して2ボランチがポジショニングをとり、ビルドアップが上手くいった。」
            5点: 「相手の中盤があまりプレスをかけてこなかったのと、相手の3トップが作るゲートに対して2ボランチがポジショニングをとり、ビルドアップが上手くいった。(07:36)」
            output only integer from 1 to 5.",
        bad: "今から入力する文章は育成年代のサッカー選手が試合を振り返って、サッカーノートの「上手くいかなかったこと」の欄に書いた文章です。
            この文章を5段階で評価してください。
            各段階ごとの評価基準を以下に記します。
            1点: サッカーの練習や試合の振り返りに関係のない文章
            2点: 上手くいかなかった現象が書かれているか
            3点: 上手くいかなかった現象と考えられる要因が書いてあるか
            4点: 上手くいかなかった現象と考えられる具体的な要因が書いてあるか
            5点: 上手くいかなかった現象と考えられる具体的な要因が書いてあり、具体的なプレーの動画内での秒数が00:00の形で示してあるか
            以下の段階ごとの文章例を参考にしてください。
            1点: 「あいうえお」「こんにちは」
            2点: 「ビルドアップが上手くいかなかった。」「サイドから崩された。」「狭いところでパスが繋がらなかった。」
            3点: 「サイドバックにボールが入った時にパスコースがなくなり、ビルドアップが上手くいかなかった。」
            4点: 「サイドバックからウイングへのパスが縦関係になり、ウイングが後ろ向きで受けることになり、ビルドアップが上手くいかなかった。」
            5点: 「サイドバックからウイングへのパスが縦関係になり、ウイングが後ろ向きで受けることになり、ビルドアップが上手くいかなかった。(07:36)」
            output only integer from 1 to 5.",
        next: ""
    }

    # ユーザーの文章を５段階評価するプロンプト(練習用)
    PROMPTS_RATE_PRACTICE = {
        good: "今から入力する文章は育成年代のサッカー選手が練習を振り返って、サッカーノートの「上手くいったこと」の欄に書いた文章です。
            この文章を5段階で評価してください。
            各段階ごとの評価基準を以下に記します。
            1点: サッカーの練習や試合の振り返りに関係のない文章
            2点: 上手くいった現象が書かれているか
            3点: 上手くいった現象と考えられる要因が書いてあるか
            4点: 上手くいった現象と考えられる具体的な要因が書いてあるか
            5点: 上手くいった現象と考えられる具体的な要因が書いてあり、具体的なプレーの動画内での秒数が00:00の形で示してあるか
            以下の段階ごとの文章例を参考にしてください。
            1点: 「あいうえお」「こんにちは」
            2点: 「ビルドアップが上手くいった。」「シュートの本数が多かった。」「相手の縦パスや地上でのビルドアップから失点することがなかった。」
            3点: 「それぞれが早めに準備していて、ビルドアップが上手くいった。」
            4点: 「3対1の時、ワンタッチ目を2人にも出せる方向に置いて相手を困らせた」
            5点: 「相手の中盤があまりプレスをかけてこなかったのと、相手の3トップが作るゲートに対して2ボランチがポジショニングをとり、ビルドアップが上手くいった。(07:36)」
            output only integer from 1 to 5.",
        bad: "今から入力する文章は育成年代のサッカー選手が試合を振り返って、サッカーノートの「上手くいかなかったこと」の欄に書いた文章です。
            この文章を5段階で評価してください。
            各段階ごとの評価基準を以下に記します。
            1点: サッカーの練習や試合の振り返りに関係のない文章
            2点: 上手くいかなかった現象が書かれているか
            3点: 上手くいかなかった現象と考えられる要因が書いてあるか
            4点: 上手くいかなかった現象と考えられる具体的な要因が書いてあるか
            5点: 上手くいかなかった現象と考えられる具体的な要因が書いてあり、具体的なプレーの動画内での秒数が00:00の形で示してあるか
            以下の段階ごとの文章例を参考にしてください。
            1点: 「あいうえお」「こんにちは」
            2点: 「ビルドアップが上手くいかなかった。」「サイドから崩された。」「狭いところでパスが繋がらなかった。」
            3点: 「サイドバックにボールが入った時にパスコースがなくなり、ビルドアップが上手くいかなかった。」
            4点: 「サイドバックからウイングへのパスが縦関係になり、ウイングが後ろ向きで受けることになり、ビルドアップが上手くいかなかった。」
            5点: 「サイドバックからウイングへのパスが縦関係になり、ウイングが後ろ向きで受けることになり、ビルドアップが上手くいかなかった。(07:36)」
            output only integer from 1 to 5.",
        next: ""
    }

    
    # 理由について言及されていない現象に対して「理由: 」のようなフォーマットを追加するプロンプト
    PROMPTS_AUTOMATIC_ADDICTION = {
        good: "今から入力する文章は育成年代のサッカー選手が練習を振り返って、サッカーノートの「上手くいったこと」の欄に書いた文章です。
            あなたのタスクは、ユーザーが言及しているそれぞれの現象に対して、理由を書くのを促すために下記の「#理由を追加するフォーマット」のようなフォーマットを追加することです。
            それぞれの現象について、理由が書かれているか、書かれていなくても既に似たようなフォーマットが含まれているかを下記の「#理由・要因が書かれているかの例」を参考にして判断し、
            フォーマットを追加すべきだと判断した場合、「#理由を追加するフォーマット」を追加してください。
            組織的な現象に対しては「#理由を追加するフォーマット(組織的)」より下の文字列を、個人的な現象に対しては「#理由を追加するフォーマット(個人的)」より下の文字列を追加する。
            現象が組織的か個人的かは下記の「#個人的な現象例」と「#組織的な現象例」を参考に判断すること。
            フォーマットを追加する必要はないと判断した場合、必ず'Nil'のみを出力してください。
            先頭に、回答に至る思考プロセスを必ず書いておいてください。
            思考プロセスの下に#自動補完を追加し、返答全体の末尾に'---'を追加すること。

            #理由・要因が書かれているかの例
                ```
                ゴール前のフィニッシュが上手くいった
                理由: インナーラップでポケットを取れた
                ```
                書かれているので、フォーマットを追加する必要はない。'Nil'を出力する。

                ```
                ゴール前のフィニッシュが上手くいった。
                理由:
                1. 
                2. 
                3. 
                ```
                既に同じフォーマットが含まれているので、フォーマットを追加する必要はない。代わりに'Nil'を出力する。

                ```
                ゴール前のフィニッシュが上手くいった。
                ```
                現象しか書かれていないので、フォーマットを追加する必要がある。

                ```
                インナーラップでポケットを取れて、ゴール前でフィニッシュが上手くいった。
                ```
                「インナーラップでポケットを取れて」の部分が「ゴール前でフィニッシュが上手くいった」ことの理由として書かれているので、フォーマットを追加する必要はない'Nil'を出力する。

            #理由を追加するフォーマット(組織的)(<ユーザーが言及している現象>にはユーザーの入力からその現象について言及している部分を抽出し、挿入すること。)
            <ユーザーが言及している現象>
            理由:
            1. 
            2. 
            3. 

            #理由を追加するフォーマット(個人的)(<ユーザーが言及している現象>にはユーザーの入力からその現象について言及している部分を抽出し、挿入すること。)
            <ユーザーが言及している現象>
            理由: 

            #個人的な現象の例
            - ミドルシュートが入った。
            - ヘディングが飛ばなかった。
            - ロングキックが飛ばなかった。
            - 一対一で勝てることが多かった。
            - 裏にタイミングよく抜け出せた。

            #組織的な現象の例
            - ビルドアップで上手く前進できた。
            - チャンスが多く作れた。

            #注意事項
            「#自動補完」より下の文章には、#がつく文を含めないこと。(下記の「#自動補完のフォーマット例」を参考にすること。)
            番号のリストが含まれている場合、番号(1. 2. 3. など)の後ろに必ず半角スペース1つを入れること。<ユーザーが言及する現象についての文>の後ろにはスペースを入れない。
            <ユーザーが言及する現象>には、ユーザーの入力のうち、その現象について言及している部分を一言一句一記号を正確に抽出し、挿入すること。

            #自動補完のフォーマット例
            #自動補完
            <ユーザーが言及する現象>
            理由:
            1. 
            2. 
            3. 
        ",
        bad: "",
        next: ""
    }

    #変更提案のプロンプト
    PROMPTS_CHANGE_SUGGESTION = {
        good: "
            今から入力する文章は育成年代のサッカー選手が練習を振り返って、サッカーノートの「上手くいったこと」の欄に書いた文章とAIによるフィードバックの文章です。
            フィードバックを反映させやすくするために、ユーザーの文章に対して部分的に変更提案をしてください。
            以下のフォーマットに従って現象に対して3つずつ提案してください。
            ですます調ではなく、だ調で出力して。

            #変更提案のフォーマット
            <ユーザーが言及する現象1>
            1. <変更提案1>
            2. <変更提案2>
            3. <変更提案3>
            ---
            <ユーザーが言及する現象2>
            1. <変更提案1>
            2. <変更提案2>
            3. <変更提案3>
            ---
        ",
        bad: "
            今から入力する文章は育成年代のサッカー選手が練習を振り返って、サッカーノートの「上手くいかなかったこと」の欄に書いた文章とAIによるフィードバックの文章です。
            フィードバックを反映させやすくするために、ユーザーの文章に対して部分的に変更提案をしてください。
            以下のフォーマットに従って現象に対して3つずつ提案してください。
            #変更提案のフォーマット
            <置き換えるユーザーの文章1>
            1. <変更提案1>
            2. <変更提案2>
            3. <変更提案3>
            ---
            <置き換えるユーザーの文章2>
            1. <変更提案1>
            2. <変更提案2>
            3. <変更提案3>
            ---
            ",
        next: ""
    }

    # ユーザーの文章に自動で文章を付け加えるためのプロンプト
    PROMPTS_ENHANCE = {
        good: "以下の文章は、サッカーの試合や練習で「上手くいったこと」について書かれています。この文章を読んで、以下の点を考慮しながら、より具体的で詳細な内容にしてください：

        1. 成功した具体的な状況や場面を追加する
        2. なぜそれが上手くいったのか、その要因を分析する
        3. そのプレーや行動がチーム全体にどのような影響を与えたかを考察する

        元の文章の内容を保持しつつ、これらの要素を追加して、より充実した振り返りになるようにしてください。書かれていない事実を含めるのは避けること。マークダウン形式で出力してください。",

        bad: "以下の文章は、サッカーの試合や練習で「上手くいかなかったこと」について書かれています。この文章を読んで、以下の点を考慮しながら、より具体的で詳細な内容にしてください：

        1. 失敗した具体的な状況や場面を追加する
        2. なぜそれが上手くいかなかったのか、その要因を分析する
        3. その失敗がチーム全体にどのような影響を与えたかを考察する
        4. 可能であれば、そのプレーが起こった時間（例：後半20分頃）を追加する
        5. この失敗を今後どのように改善できるか、簡単な提案を加える

        元の文章の内容を保持しつつ、これらの要素を追加して、より充実した振り返りになるようにしてください。書かれていない事実を含めるのは避けること。マークダウン形式で出力してください。",

        next: "以下の文章は、サッカーの試合や練習の後、「次に意識すること・次に向けて取り組むこと」について書かれています。この文章を読んで、以下の点を考慮しながら、より具体的で実行可能な内容に拡張してください：

        1. 具体的な練習方法や取り組みを提案する
        2. なぜその取り組みが重要なのか、その理由を説明する
        3. その取り組みによってどのような成果が期待できるかを述べる
        4. 可能であれば、短期的な目標と長期的な目標を区別して提案する
        5. チーム全体で取り組むべきことと個人で取り組むべきことを区別する

        元の文章の内容を保持しつつ、これらの要素を追加して、より具体的で実践的な計画になるようにしてください。マークダウン形式で出力してください。"
    }

    def perform(note_for, channel, input, type, token, user_id, group_id, response_id)
        if input && input != ""
            response = Response.find(response_id)
            target = "notes_#{type}"
            rate_prompt = nil
            if type != "next" && note_for == "match"
                p "rating..."
                if note_for == "match"
                    rate_prompt = PROMPTS_RATE_MATCH[type.to_sym]
                elsif note_for == "practice"
                    rate_prompt = PROMPTS_RATE_PRACTICE[type.to_sym]
                end

                rate_response_from_gpt4o_mini = OpenAI::Client.new.chat(
                    parameters: {
                        model: MODEL_NAME,
                        messages: [{ role: "system", content: rate_prompt }, { role: "user", content: input}],
                        temperature: TEMPERATURE,
                        max_tokens: 10,
                        n: RESPONSES_PER_MESSAGE
                    }
                )

                rate = rate_response_from_gpt4o_mini.dig("choices", 0, "message", "content")

                Turbo::StreamsChannel.broadcast_replace_later_to(
                    "rate_" + channel,
                    target: "notes_#{type}_rate",
                    partial: "notes/rate",
                    locals: { rate: rate.to_i, target: "notes_#{type}_rate" }
                )
            end

            if note_for == "match"
                previous_messages = []
                previous_note = "#前回のノート\n"
                latest_note = Note.where(user_id: user_id, group_id: group_id, note_for: "match").order(created_at: :desc).first
                if latest_note
                    previous_note += "上手くいったこと: \n"
                    previous_note += "#{latest_note.good}\n"
                    previous_note += "上手くいかなかったこと: \n"
                    previous_note += "#{latest_note.bad}\n"
                    previous_note += "次に意識すること・次に向けて取り組むこと: \n"
                    previous_note += "#{latest_note.next}\n"
                    previous_note += "チームで話し合いたいこと・確認したいこと: \n"
                    previous_note += "#{latest_note.discuss.to_s}\n"
                else
                    previous_note = ""
                end

                prompt = PROMPTS_MATCH[type.to_sym] + previous_note

                previous_messages << { role: "system", content: prompt }

                # 追加: 前回の会話履歴を取得
                conversation_history = get_conversation_history(type, user_id, token, response_id)
                p :conversation_history, conversation_history
                conversation_history.each do |msg|
                    previous_messages << { role: msg[:role], content: msg[:content] }
                end

                # 現在のユーザー入力をメッセージに追加
                previous_messages << { role: "user", content: input }
                p :previous_messages, previous_messages
            elsif note_for == "practice"
                previous_messages = []

                group = Group.find(group_id)
                previous_note = "前回のノート:\n"
                latest_note = Note.where(user_id: user_id, group_id: group_id, note_for: "practice").order(created_at: :desc).first
                if latest_note
                    previous_note += "上手くいったこと: \n"
                    previous_note += "#{latest_note.good}\n"
                    previous_note += "上手くいかなかったこと: \n"
                    previous_note += "#{latest_note.bad}\n"
                    previous_note += "次に意識すること・次に向けて取り組むこと: \n"
                    previous_note += "#{latest_note.next}\n"
                    previous_note += "チームで話し合いたいこと・確認したいこと: \n"
                    previous_note += "#{latest_note.discuss.to_s}\n"
                else
                    previous_note = ""
                end
                if group.daily_practice.daily_practice_items.length != 0
                    content_of_practice = "今日の練習内容:\n"
                    group.daily_practice.daily_practice_items.each do |daily_practice_item|
                        practice_name = daily_practice_item.practice.name
                        number_of_people = daily_practice_item.practice.number_of_people
                        solvable_issues = daily_practice_item.practice.issue
                        key_points = daily_practice_item.practice.key_points
                        applicable_situation = daily_practice_item.practice.applicable_situation
                        content_of_practice += "練習メニュー名: #{practice_name}\n"
                        content_of_practice += "トレーニング内容: #{daily_practice_item.practice.introduction}\n"
                        content_of_practice += "練習時間(分): #{daily_practice_item.training_time}\n"
                        content_of_practice += "意識するポイント: #{key_points}\n"
                        content_of_practice += "試合で該当するシチュエーション: #{applicable_situation}\n"
                        content_of_practice += "解決する課題: #{solvable_issues}\n"
                    end
                else
                    content_of_practice = ""
                end

                prompt = PROMPTS_PRACTICE[type.to_sym] + previous_note + content_of_practice + conversation_history

                previous_messages << { role: "system", content: prompt }

                # 会話履歴を取得してメッセージに追加
                conversation_history = get_conversation_history(type, user_id, token, response_id)
                conversation_history.each do |msg|
                    previous_messages << { role: msg[:role], content: msg[:content] }
                end

                # 現在のユーザー入力をメッセージに追加
                previous_messages << { role: "user", content: input }
            end

            response_from_gpt4o_mini = OpenAI::Client.new.chat(
                parameters: {
                    model: MODEL_NAME,
                    messages: previous_messages,
                    temperature: TEMPERATURE,
                    max_tokens: 1000,
                    n: RESPONSES_PER_MESSAGE
                }
            )

            message = response_from_gpt4o_mini.dig("choices", 0, "message", "content")
            p :message, message
            response.update(response: message)

            automatic_addiction_response = OpenAI::Client.new.chat(
                parameters: {
                    model: MODEL_NAME,
                    messages: [{ role: "system", content: PROMPTS_AUTOMATIC_ADDICTION[type.to_sym] }, { role: "user", content: input}],
                    temperature: TEMPERATURE,
                    max_tokens: 500,
                    n: RESPONSES_PER_MESSAGE
                }
            )

            auto_addiction = automatic_addiction_response.dig("choices", 0, "message", "content")
            p :auto_addiction, auto_addiction

            if auto_addiction.include?("Nil")
                auto_addiction = ""
            else
                #自動補完から始まって末尾が"---"で終わる文字列を抽出
                auto_addiction = extract_suggestion(auto_addiction)
            end


            suggestion_response = OpenAI::Client.new.chat(
                parameters: {
                    model: MODEL_NAME,
                    messages: [{ role: "system", content: PROMPTS_CHANGE_SUGGESTION[type.to_sym] }, { role: "user", content: input + "AIによるフィードバック:\n" + message}],
                    temperature: TEMPERATURE,
                    max_tokens: 1000,
                    n: RESPONSES_PER_MESSAGE
                }
            )

            suggestion = suggestion_response.dig("choices", 0, "message", "content")
            suggestions = suggestion.split('---').map(&:strip)
            p :suggestions, suggestions

            Turbo::StreamsChannel.broadcast_replace_later_to(
                channel,
                target: "notes_#{type}",
                partial: "notes/message",
                locals: { message: message, target: target, diff_content: auto_addiction, suggestion: suggestions[0] }
            )

            # スピナーを停止
            Turbo::StreamsChannel.broadcast_replace_later_to(
                "spinner",
                target: "spinner_#{type}",
                partial: "spinner/hide",
                locals: {target: "spinner_#{type}"}
            )
        end
    rescue Faraday::BadRequestError => e
        Rails.logger.error("BadRequestError: #{e.message}")
        Rails.logger.error("OpenAI API Response: #{e.response[:body]}") # 追加
    rescue => e
        Rails.logger.error("Unexpected error: #{e.message}")
    end

    private

    # 会話履歴を取得するメソッド
    def get_conversation_history(section_type, user_id, token, response_id)
        # 過去のレスポンスを取得
        responses = Response.where(section_type: section_type, user_id: user_id, token: token)
                            .where('id < ?', response_id)
                            .order(created_at: :asc)
        if responses
            history = []
            responses.each do |resp|
                history << { role: "user", content: resp.input }
                history << { role: "assistant", content: resp.response }
            end
            return history
        else
            return []
        end
    end

    # 「#自動補完」から「---」までの文字列を抽出するメソッド
    def extract_suggestion(message)
        match_data = message.match(/#自動補完(.*?)---\s*\z/m)
        if match_data
            suggestion = match_data[1] if match_data
            suggestion
        else
            match_data = message.match(/#理由・要因のフォーマット(組織的)(.*?)---\s*\z/m)
            if match_data
                suggestion = match_data[1] if match_data
                suggestion
            else
                match_data = message.match(/#理由・要因のフォーマット(.*?)---\s*\z/m)
                if match_data
                    suggestion = match_data[1]
                    suggestion
                else
                    return nil
                end
            end
        end
    end
end