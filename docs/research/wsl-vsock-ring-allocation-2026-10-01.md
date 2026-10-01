---
type: research
title: WSL の VMBus ring 高次割当失敗と設定のみの比較候補
description: WSL 3.0.1・kernel 6.18.40.1 の vsock ring 割当状況、公式上流修正の採用・配布範囲、設定での軽減根拠と次の比較実験を一次資料で調べる。
tags: [research, wsl, linux-kernel, memory, vsock]
timestamp: 2026-10-01
---

# WSL の VMBus ring 高次割当失敗と設定のみの比較候補

初回調査の基準時点は **2026-10-01 JST**。対象は WSL 3.0.1、Microsoft WSL kernel 6.18.40.1、および同日時点の Linux master。主張は、一次資料で確かめた事実、ローカル実測、そこからの推論、未確認事項に分ける。

## 結論

- **公式配布 kernel にこの ring 割当失敗を直す変更は確認できない。** WSL2-Linux-Kernel の最新 release と `linux-msft-wsl-6.18.y` branch tip はどちらも `linux-msft-wsl-6.18.40.1`、commit `14794180686c2fb6307fbe359c359bec765249f3`。その `vmbus_alloc_ring()` は現在も `alloc_pages_node()` と `alloc_pages()` を試し、失敗時に `-ENOMEM` を返す。[公式 kernel release](https://github.com/microsoft/WSL2-Linux-Kernel/releases/tag/linux-msft-wsl-6.18.40.1)・[固定 commit の channel.c](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/drivers/hv/channel.c#L167-L194)
- **上流の `vmbus_alloc_buffer()` 採用は netvsc の送受信 GPADL buffer 用で、ring 修正ではない。** Linux master `551c722f40809618230001baccf219193e22fc5a` では `netvsc.c` がこの helper を使う一方、同じ tree の `vmbus_alloc_ring()` は依然として高次 `alloc_pages()` を使う。[netvsc の使用箇所](https://github.com/torvalds/linux/blob/551c722f40809618230001baccf219193e22fc5a/drivers/net/hyperv/netvsc.c#L380-L384)・[ring allocator](https://github.com/torvalds/linux/blob/551c722f40809618230001baccf219193e22fc5a/drivers/hv/channel.c#L171-L198)。Michael Kelley の9月22日のレビューも、単純な `vzalloc()` fallback は一部の CoCo VM に適合せず、ring への `vmbus_alloc_buffer()` 適用案はまだコード化していないと明記している。[本人の LKML review](https://www.mail-archive.com/linux-kernel%40vger.kernel.org/msg2658605.html)
- **カーネルを作り直さない実験候補はあるが、解決済みの回避策ではない。** 次は `.wslconfig` の `kernelCommandLine=sysctl.vm.defrag_mode=1` を起動時から有効にする比較を推奨する。初回調査時の値0に対し、Linux kernel 文書がこの knob の目的を「higher-order pages を得られる状態を保つため allocator が fragmentation を避ける」とし、断片化が長く残り得るので起動直後の有効化を勧めているためである。[Linux VM sysctl 文書](https://docs.kernel.org/admin-guide/sysctl/vm.html#defrag-mode) この効果はまだ実測されていない。
- メモリ関連の sysctl や `autoMemoryReclaim` は、空き総量・reclaim・compaction の振る舞いを変えるが、**要求中の物理連続領域が必ず作られる保証にはならない**。数値を根拠なく変えない。

## 公式 kernel と WSL runtime の採用状況

| 対象 | 2026-10-01 時点の確認 | この障害との関係 |
| --- | --- | --- |
| WSL runtime | 最新 GitHub release は 3.0.1（2026-09-29公開）。[release](https://github.com/microsoft/WSL/releases/tag/3.0.1) | release notes にある session/VM termination の待機時間変更は、物理連続領域の ring 割当を変えるものではない。ローカル更新後も `accept4 failed 110` が残った。 |
| Microsoft WSL kernel | 最新 release は 6.18.40.1。branch tip と release tag は同じ commit `14794180686c2fb6307fbe359c359bec765249f3`。[release](https://github.com/microsoft/WSL2-Linux-Kernel/releases/tag/linux-msft-wsl-6.18.40.1) | 固定ソースの ring allocator は node-local と通常 allocator の高次割当に失敗すると `-ENOMEM` を返す。[channel.c](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/drivers/hv/channel.c#L167-L194) |
| Linux master | 2026-09-30 の master commit `551c722f40809618230001baccf219193e22fc5a` を確認。[commit](https://github.com/torvalds/linux/commit/551c722f40809618230001baccf219193e22fc5a) | netvsc は8月24日の `vmbus_alloc_buffer()` 採用 commit `f85e1cc5ecbbbb18ac68639f667c9de49b3ca986` を含むが、ring は依然 `alloc_pages()`。[netvsc](https://github.com/torvalds/linux/blob/551c722f40809618230001baccf219193e22fc5a/drivers/net/hyperv/netvsc.c#L380-L384)・[channel.c](https://github.com/torvalds/linux/blob/551c722f40809618230001baccf219193e22fc5a/drivers/hv/channel.c#L171-L198) |
| ring 向け案 | 9月17日に `vzalloc()` fallback の patch が投稿され、9月22日に Michael Kelley が review。[review](https://www.mail-archive.com/linux-kernel%40vger.kernel.org/msg2658605.html) | Kelley は arm64 CCA と paravisor なし TDX では `set_memory_decrypted()` が vmalloc memory に使えない制約を指摘。新 helper を ring 全体で使う案は「まだコード化していない」と述べている。公式 WSL release に入った修正ではない。 |

ここでいう「確認できない」は、上記の latest official release/tag と immutable source に変更がないという意味であり、将来の採用予定を否定するものではない。WSL 3.0.1 は WSL runtime release、6.18.40.1 は別配布の kernel release であり、runtime version の新しさを kernel ring fix の根拠にしない。[WSL kernel release notes](https://github.com/microsoft/WSL2-Linux-Kernel/releases/tag/linux-msft-wsl-6.18.40.1)

## 障害箇所と今回までの実測

以下の実測は Ubuntu-24.04、WSL 3.0.1.0、kernel `6.18.40.1-microsoft-standard-WSL2`、dotfiles commit `c2c638de10219967a08e2591f2b888c18249ec0b` の作業環境で取得した記録である。参照する `tmp/` 配下は Git 管理対象外で、別の checkout には含まれないため、判断に必要な数値は本文にも残す。

固定した WSL kernel source の `vmbus_alloc_ring()` は、send と receive の合計サイズから order を計算し、物理ページを連続して取得する。ローカル kernel log の `order:7` は 4 KiB page × 2⁷ = **512 KiB の連続領域**が取れなかった記録と一致する。`MemAvailable` の大きさだけでは、特定 zone にそのサイズの割当可能な block があるか分からない。[WSL kernel source](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/drivers/hv/channel.c#L167-L194)

ローカル記録では WSL 2.7.14 / kernel 6.18.33.2 から WSL 3.0.1 / kernel 6.18.40.1 へ更新して再起動した後も、同じ `UtilAcceptVsock: accept4 failed 110` が発生した。全体負荷中の実 PowerShell 32並列1,000回で28回、負荷終了後の Dogfood 4並列40回で2回発生した。kernel log には `vmbus_alloc_ring` 経由の order-7 allocation failure が記録された。[再検証記録](../../tmp/wsl-recheck/README.md)

今回承認済みで実施した compaction 1回の比較では、同一コマンドの64並列64回 probe の結果は以下だった。背景負荷は時間とともに変化しており、自然回復を含む時間変動が大きいため、40→18を効果とは扱わない。

| 条件              | 成功 | `vsock110` |
| ----------------- | ---: | ---------: |
| 基準              |   24 |         40 |
| 無操作 control    |   60 |          4 |
| 1回 compaction 後 |   46 |         18 |

compaction 前後は `MemAvailable` が約10.7 GiB。page type の取得時点では Normal zone の通常 migrate type に order 7 の block がなく、HighAtomic 用 block は残り、DMA32 の大きな領域も増えていなかった。kernel order-7 warning は16→18→18→19件へ推移した。この証拠は高次割当失敗と整合する一方、全ての zone allocator 状態を原子的に示すものではない。[compaction summary](../../tmp/wsl-kernel-debug/compact-summary.json)・[実測の説明](../../tmp/wsl-recheck/README.md)

また、8 GiB sparse file の読み込み後、その file cache 約2.8 GBだけを `POSIX_FADV_DONTNEED` で解放する比較は前後とも64回成功だった。したがって cache 量だけで再現を説明できず、この結果は `autoMemoryReclaim` の効果を示すものでもない。[実測記録](../../tmp/wsl-recheck/README.md)

## 設定だけで変えられる範囲

### VM memory / swap / reclaim

`.wslconfig` の `memory` は WSL 2 VM の割当上限、`swap` は disk-based swap のサイズ、`processors` は CPU 数である。`memory` の引上げは上限が実際の圧力源で、Windows に十分な RAM がある場合にだけ圧力を緩める候補になる。空き総量を増やしても order-7 block の連続性は保証しない。swap は物理連続 RAM の代用品ではなく、`processors` は ring の page allocation を直接変えない。[Microsoft `.wslconfig` docs](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)

初回調査時の実機 `.wslconfig` には `memory`、`swap`、`autoMemoryReclaim`、`kernelCommandLine` の明示設定がない。現行 Microsoft docs の `autoMemoryReclaim` 既定値は `dropCache` で、`gradual` は cached memory を徐々に、`dropCache` は即時に回収する。ただし設定ファイルにキーがないことだけから、実行中 VM の有効値を実測したとは扱わない。reclaim の対象は cache であり、動作中プロセスの anonymous memory や VMBus ring allocator を直接変更する設定ではない。`dropCache` / `gradual` を切り替える実験には cache 再読込の I/O コストがあり、今回の file-specific cache release 結果から改善を予測できない。[Microsoft `.wslconfig` docs](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)・[Linux drop_caches docs](https://docs.kernel.org/admin-guide/sysctl/vm.html#drop-caches)

### Linux VM sysctl

| 設定 | 初回調査時の値 | 公式資料が示す作用 | この症状への評価 |
| --- | --: | --- | --- |
| `vm.min_free_kbytes` | 45,056 KiB | zone ごとの最低 free-page watermark を計算する。高すぎる値は OOM を招き得る。[kernel docs](https://docs.kernel.org/admin-guide/sysctl/vm.html#min-free-kbytes) | free-page reserve を増やすとアプリが使えるメモリを減らす。高次連続 block の生成保証にはならず、増量値は推奨しない。 |
| `vm.watermark_scale_factor` | 10 | `kswapd` の起床・停止水位の間隔を調整する。既定10は node memory に対する0.1%。[kernel docs](https://docs.kernel.org/admin-guide/sysctl/vm.html#watermark-scale-factor) | 低 watermark / direct reclaim の観測があれば調査候補だが、今回その必要性を示す根拠は不足。先に上げない。 |
| `vm.watermark_boost_factor` | 15,000 | mobility type が混ざった pageblock の fragmentation を検知した後に reclaim する割合を制御する。既定15,000は high watermark の最大150%。[kernel docs](https://docs.kernel.org/admin-guide/sysctl/vm.html#watermark-boost-factor) | 既に kernel docs の既定値。高次割当失敗を単独で防ぐ保証はない。 |
| `vm.compaction_proactiveness` | 20 | 既定20、範囲0–100。背景 compaction の積極度を変え、非0値の書込みは直ちに proactive compaction を起動する。過度な activity と全体 latency spike に注意。[kernel docs](https://docs.kernel.org/admin-guide/sysctl/vm.html#compaction-proactiveness) | 既定値。今回の手動 compaction 1回は未解消で、値上げが改善する証拠はない。 |
| `vm.extfrag_threshold` | 500 | `extfrag_index` が threshold 以下の zone では kernel は compaction しない。既定500。[kernel docs](https://docs.kernel.org/admin-guide/sysctl/vm.html#extfrag-threshold) | zone/order 別 `extfrag_index` を確認せず変更値を決めない。 |
| `vm.defrag_mode` | 0 | 1にすると page allocator が fragmentation を避け higher-order / huge pages を作れる状態を保とうとする。kernel docs は boot 直後の有効化を推奨する。[kernel docs](https://docs.kernel.org/admin-guide/sysctl/vm.html#defrag-mode) | 起動後の一回限りの compaction と異なり、断片化が進む前から allocator の判断を変える。この環境での効果は未検証。 |

### VSOCK socket default の別経路

もう一つの設定候補は `net.core.rmem_default` と `net.core.wmem_default`。実機の read-only 値は両方212,992 bytes（maxは両方4 MiB）。Linux は socket 作成時にこの値を `sk_rcvbuf` / `sk_sndbuf` へコピーし、WSL 3.0.1 の `UtilListenVsockAnyPort()` は `socket(AF_VSOCK)`、`bind()`、`listen()` を呼ぶが `SO_RCVBUF` / `SO_SNDBUF` を設定しない。[WSL init source](https://github.com/microsoft/WSL/blob/3.0.1/src/linux/init/util.cpp#L1596-L1618)・[Linux sock.c](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/net/core/sock.c#L3652-L3655)

WSL kernel の `hvs_open_connection()` は host から来た接続では bound listener を `sk` として ring hint に使う。VMBus protocol が `VERSION_WIN10_V5` 以上の場合、送受信ごとに24 KiB minimum / 256 KiB maximum と page alignment・header を適用して `vmbus_open()` を呼ぶ。旧 protocol では固定の小さい ring を使う。[listener の取得](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/net/vmw_vsock/hyperv_transport.c#L295-L342)・[ring size calculation](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/net/vmw_vsock/hyperv_transport.c#L359-L387)。このため、**対応する protocol で新 listener に default socket buffer を小さく適用できれば ring order を下げ得る**という経路はソース上存在する。

ただし sysctl 変更は既存 listener に遡及せず、`rmem_default` / `wmem_default` は net.core defaults に依存する socket 全般へ影響する。TCP には `tcp_rmem` / `tcp_wmem` という個別 default があり net.core 値を上書きする。[kernel net sysctl docs](https://docs.kernel.org/admin-guide/sysctl/net.html#rmem-default)・[kernel IP sysctl docs](https://docs.kernel.org/6.18/networking/ip-sysctl.html)。今回、自作 AF_VSOCK listener の `getsockopt()` でも送受信 default が両方212,992 bytesであることを確認した。この socket だけに `SO_RCVBUF` / `SO_SNDBUF` を32,768として設定すると、読み戻しは両方65,536だった。socket は閉じており、共有 sysctl は変更していない。この確認は default の継承と個別設定だけを示し、Windows から接続した listener の再生成・ring size・interop 成功は検証していない。設定値を下げたときの通常 socket / VSOCK throughput への影響も未測定である。

これは割当要求の発生元により近い別候補だが、今回の一件目の比較には選ばない。効果が新 listener の生成順に依存し、VSOCK 以外の新規 socket buffer も変え、実際の Windows 主導接続で end-to-end 検証がまだないためである。将来の比較値を置くなら、`sysctl` 値と ring order の算術だけで成功扱いにせず、Windows 接続時の実際の ring allocation を記録して判断する。

## 初回調査で推奨した比較実験

**一項目だけ変更し、boot-time `vm.defrag_mode=1` と現状値0を fresh boot 同士で比べる。** Linux kernel docs が高次ページの維持を直接目的とし、断片化が起きる前の boot 直後設定を勧める。先行の手動 compaction 結果が未解消だったため、既存断片を後から動かす実験より仮説を区別できる。

1. 元の `.wslconfig` を保持したまま `wsl --shutdown` して distro を新規起動し、baseline を取得する。boot ID の変更と `/proc/sys/vm/defrag_mode` が0であることを確認する。commit、Nix の固定入力、全 Bats suite・Rust/Elixir/Perl template 検証の負荷、probe を開始するタイミングと順序を固定する。PowerShell は32並列1,000回と64並列64回、Dogfood は4並列40回を両条件で同じ順序で実施する。実行前後の `MemAvailable`、`/proc/buddyinfo`、`/proc/pagetypeinfo`、order-7 kernel warning 差分、失敗ログを保存する。
2. 元の Windows `.wslconfig` を byte 単位で退避してから、既存の `[wsl2]` section に次の1行だけを加える。値1は sysctl の有効値で、別のメモリ設定や auto-reclaim 設定を同時に変更しない。

   ```ini
   kernelCommandLine=sysctl.vm.defrag_mode=1
   ```

   `.wslconfig` の `kernelCommandLine` は追加 kernel 引数を取る。Linux の `sysctl.*` boot parameter は init process の起動直前に `/proc/sys/...` へ設定する。この機構は WSL kernel の固定 tag にもあり、`init/main.c` から `do_sysctl_args()` を init 起動前に呼び、`proc_sysctl.c` が引数を処理する。`page_alloc.c` は `defrag_mode` を0..1で登録している。[Microsoft `.wslconfig` docs](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)・[Linux `sysctl.*` parameter](https://docs.kernel.org/admin-guide/kernel-parameters.html#kernel-parameters)・[WSL init order](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/init/main.c#L1505)・[WSL sysctl argument handler](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/fs/proc/proc_sysctl.c#L1710)・[WSL defrag_mode registration](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/mm/page_alloc.c#L6737)。起動後の readback はまだ検証していない。

3. 設定適用のため再度 `wsl --shutdown` 後に distro を起動する。`.wslconfig` は全 WSL 2 distro 共通であり、この shutdown は全ての稼働 distro を止める。[Microsoft shutdown/config docs](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#the-8-second-rule-for-configuration-changes)。変更後は boot ID の変更、`/proc/cmdline` に `sysctl.vm.defrag_mode=1` が存在すること、`/proc/sys/vm/defrag_mode` が `1` であること、引数に関する kernel error がないことを負荷前に確認する。違う場合は負荷を始めず失敗として記録する。
4. baseline と同じ workload / probe 順序・並行数で走らせ、同じ kernel / buddy / memory 記録を取る。成功率だけでなく、追加された order-7 failure 数、zone ごとの order-7 以上 free block、実行時間も比べる。自然回復は過去に64 probe 中40件から control 4件まで変動したため、各条件一回の成否を効果と断定しない。両条件で障害が再現しなければ改善の根拠は得られない。改善が見えても予備結果として扱い、再現性の確認を経て継続使用を判断する。
5. rollback は退避した `.wslconfig` bytes を元の場所へ復元し、もう一度 `wsl --shutdown` して起動する。`/proc/sys/vm/defrag_mode` が0へ戻ったことを確認する。設定ファイルを削除する必要はない。

比較には少なくとも2回の共有 WSL 再起動が必要で、rollback も行う場合はさらに1回必要になる。既に断片化した現在の0状態と、新規起動した1状態を直接比べると、再起動による回復を設定の効果と誤認するため、この手順では両条件を新規起動から揃える。

この設定は WSL 2 VM 内の page allocator 全体に適用されるため、VMBus 専用ではない。実装は fragmentation を避ける判断と `kswapd` に要求する reclaim order を変える一方、reclaim/compaction 後の fallback は許容するため、断片化を完全に防ぐ保証ではない。[reclaim order の変更](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/mm/page_alloc.c#L4442-L4451)・[fallback の許容](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/mm/page_alloc.c#L4912-L4922)。allocation latency / CPU 使用が上がる可能性は実装からの推論で、WSL での実測は未確認。元の `.wslconfig` の変更、共有 VM の再起動、比較実験はいずれも今回の research では行っていない。

## 未確認事項

- `vm.defrag_mode=1` がこの WSL workload で order-7 allocation または vsock110 を減らすか。
- WSL init の各 host-open listener が sysctl 後に新規作成されるか、また `net.core.rmem_default` / `wmem_default` の変更が実 Windows interop ring を縮めるか。
- `.wslconfig` から実行中の `autoMemoryReclaim` mode を確実に読む手段と、その実験による効果。
- fragmentation の全発生源。`MemAvailable` や cache の量だけでは説明できず、現在の証拠から個別 workload の寄与は断定できない。

## 設定追加・再起動後の再検証（2026-10-01 JST）

ユーザーが `.wslconfig` に `kernelCommandLine=sysctl.vm.defrag_mode=1` を追加して WSL を再起動した後、同じ dotfiles commit で検証した。boot ID は `df0a6e66-e109-4fd8-bdf1-d6dab73e9d48` へ変わり、起動引数と `/proc/sys/vm/defrag_mode` の読み戻しで値1を確認した。WSL 3.0.1.0 / kernel 6.18.40.1、その他の VM sysctl 値は前回と同じ。テンプレートの固定入力も前回と一致している。

**今回の設定後検証はすべて成功し、元の vsock タイムアウトは再現しなかった。**

| 検証 | 結果 |
| --- | --- |
| 全 Bats suite（plan 722） | 700成功・22スキップ・失敗0、exit 0 |
| Rust・Elixir・Perl の実テンプレート | 各3システム評価、devShell、with-env、環境変数の隔離、実 raw entry 内の実行・テスト・コミット・再起動まで成功、exit 0 |
| 無負荷 Node、実 PowerShell 64並列64回 | 64成功・vsock110 0・その他0 |
| 全テスト・テンプレートの負荷中、実 PowerShell 32並列1,000回 | 1,000成功・vsock110 0・その他0 |
| 負荷中、Node / Python 各64並列64回 | 各64成功・vsock110 0・その他0 |
| 空きメモリが減った段階、Node 64並列64回 | 64成功・vsock110 0・その他0 |
| 負荷終了後、実 Dogfood 直列10回・4並列40回 | 計50成功・vsock110 0・その他0、Chrome 起動・CDP 接続・終了処理を含む |
| kernel の order-7 allocation warning | 開始前0件・終了後0件 |

実 PowerShell は合計1,256回すべて成功。前回 vsock タイムアウトで失敗した Bats の annotation / Windows inspection の2ケースも成功した。結果と各終了コード、kernel / memory 記録は [再検証の summary](../../tmp/wsl-defrag-recheck/summary.json)、説明は [再検証記録](../../tmp/wsl-defrag-recheck/README.md) に保存した。Dogfood 50試行の evidence も作業用ディレクトリへ退避した。これらの `tmp/` 資料は Git 管理対象外である。

検証中の共有 VM 全体では `allocstall_normal` が5,468、`compact_stall` が106,682、`compact_fail` が103,199、`compact_success` が3,483増えた。これらは direct reclaim / compaction の活動回数で、待機時間ではない。[ALLOCSTALL の計数](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/mm/vmscan.c#L6404)・[COMPACTSTALL の計数](https://github.com/microsoft/WSL2-Linux-Kernel/blob/14794180686c2fb6307fbe359c359bec765249f3/mm/page_alloc.c#L4156)。同じ時間幅・負荷の mode0 対照がないため、この増加を設定変更の効果量や性能劣化の証拠とは扱わない。

今回、mode0 の fresh-boot 対照は取得していない。従って、**設定の効果と再起動による回復は分離できず、恒久修正や性能影響も未確定**である。初回に提案した A/B 比較全体が完了したという結果ではなく、ユーザーが設定した mode1 の起動後検証として記録する。agent による共有設定変更、追加 compaction、追加再起動は行っていない。
