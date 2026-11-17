# Birleştirme protokolünün TLA+ belirtimi

Dosyalar: `merge.tla` (model), `merge.cfg` (kodun yaptığı protokol), `merge-<hata>.cfg` (sekiz bozulmuş varyant). Çalıştırma: `sh tests/tlc.sh docs/formal/merge.cfg`; test: `sh tests/formal_test.sh` (Java ve `tla2tools` 1.8.0 gerekir, jar'ın SHA-256'sı `tests/tlc.sh`'te sabittir: `7e53aa636dac8a3cb0533f343115c0548e03fc0ce5edc7739becf58d3d0fb84f`; yoksa test başarısız olur, yalnızca `SW_SKIP_FORMAL=<gerekçe>` onu gerekçesiyle görünür biçimde atlar). TLC paketin değil bu reponun geliştirme bağımlılığıdır.

Son doğrulandığı commit: `3b87b51` (kod: `src/lib/lock.sh`, `admit.sh`, `worktree.sh`, `merge.sh`, `queue.sh`, `run.sh`, `job.sh`). TLC: `TLC2 Version 2026.11.15.002146 (rev: bc1b506)`, 4 işçi.

## Değişmezler: düz cümle ve zarar

| Ad | Düz cümle | Bozulursa zararı |
| --- | --- | --- |
| `GateBeforeMerge` | `gh pr merge` çağrılan her SHA'da `guard` ve `verify` geçmiştir; geçmemiş bir SHA'yı döngü entegrasyona birleştirmez. | Kapıdan geçmemiş (korunan yolu değiştiren, testi gevşeten, kırık) kod, insan görmeden entegrasyon dalına girer. |
| `NoMergeWhileHalted` | Koşu durmuşken (`halted`) hiçbir birleştirme başlamaz. | Entegrasyon dalı kırmızıyken ve geri alma PR'ı beklenirken üstüne birleştirmek kırmızıyı derinleştirir ve geri almayı imkânsızlaştırır. |
| `NoOverlap` | `touches`'ı kesişen iki iş, ikisi de son durumda değilken (bekleyenler dahil) birlikte var olmaz. | İki iş aynı dosyayı değiştirir; sonraki birleştirme çakışır ya da sessizce birinin işini ezer. |
| `SingleMerger` | Aynı anda en fazla bir `gh pr merge` çağrısı sürer. | İki birleştirme üst üste biner; ikincisi birincinin değişikliğini görmeden doğrulanmış SHA'yla birleşir ve entegrasyon doğrulanmamış bir ağaca döner. |
| `QueueKept` | `queued` olan her iş kuyruktadır ve kuyruktaki her iş `queued`'dır, bir kez. | İş kuyruktan kaybolur (kimse birleştirmez) ya da işlenmiş bir iş kuyrukta kalıp ikinci kez birleştirilmeye çalışılır. |
| `QueueOwned` | Kuyrukta iş varken birleştirme kilidini tutan biri vardır (ölü sahip de sayılır, sonraki istekçi kırar); tek istisna boşaltıcının koşu durduğu için kilidi bilerek bırakmasıdır. | İş kuyrukta sahipsiz kalır: kimse boşaltmaz, ta ki birinin `queue drain` çalıştırması aklına gelene kadar. |
| `MergedOnce` | Bir iş için `gh pr merge` en fazla bir kez çağrılır; zaten birleşmiş PR yalnızca kaydedilir. | Çöken boşaltıcıdan sonra aynı PR ikinci kez birleştirilmeye çalışılır; hata döner, iş boş yere insana gider ya da çift birleştirme olur. |
| `Progress` (zamansal) | Çöküşler sonlu oldukça başlayan her iş `merged` olur, `escalated` olur (insana gelir) ya da koşu durur (insanın sırası). Kurtarma ve boşaltma eylemleri zayıf adilidir. | Ölü bir sürecin kilidi ya da kuyruğu işi sonsuza dek tutar; döngü sessizce takılır. |

Planın D-108 eşlemesinden sapma (D-111): `racyrelease` varyantı `Progress`'i değil `QueueOwned`'ı bozar. Nedeni: boşaltma eylemleri adil olduğu için (orkestratörün `run next` → `drain` yolu) sahipsiz kalmış kuyruk eninde sonunda boşaltılır ve `Progress` hâlâ geçer; sahipsizlik güvenlik özelliğiyle (`QueueOwned`) yakalanır. `QueueKept` için plan varyant vermemişti; `splitdequeue` eklendi. `MergedOnce` ve `norecover` da eklendi (AC-V4-11: zaten birleşmiş PR ikinci kez birleştirilmez). `Resume` ve `ExtFix` eylemleri, `NoMergeWhileHalted`'ın bozulmuş varyantta gerçekten ihlal edilebilmesi için modele girdi (aksi hâlde kırmızı uçta sonraki işin `verify`'ı zaten kaybederdi ve değişmez boş olurdu).

## Model: eylem → dosya ve fonksiyon

Durum kilidi altındaki her bölüm modelde tek eylemdir; kilit dışındaki her adım ayrı eylemdir. `merge` kilidi modelde açık bir değişkendir (`lock`).

| Eylem | Koddaki karşılığı |
| --- | --- |
| `Start(j)` | `sw_admit_locked` (`src/lib/admit.sh`), `sw_job_start` (`src/lib/job.sh`) içinde `sw_state_locked` altında: koşu açık ve durmamış, `concurrency`, `touches` kesişmesi (`sw_admit_overlap`), iş kaydı (`ready`) ve `git worktree add` (`sw_wt_add`, `src/lib/worktree.sh`) tek bölüm. |
| `Begin(j)` | `sw_job_start`: `bootstrap` (`sw_wt_bootstrap`, kilit dışı) ve `start` olayı (`sw_job_apply`). |
| `Escalate(j)` | `sw_job_apply` (`escalate`); çalışma sırasında bütçe, tur sınırı ya da ajanın sorusu. |
| `EnqueueDrain(j,p)`, `EnqueueBusy(j)` | `sw_merge_enqueue_locked` (`src/lib/merge.sh`): kuyruğa ekleme (`sw_queue_add`), `enqueue` olayı (`sw_job_apply`) ve `sw_lock_try merge` (`src/lib/lock.sh`; ölü sahibi kırar) tek durum kilidi bölümünde. Kilit alınırsa bu süreç boşaltıcıdır (`sw_queue_drain`), alınmazsa `queued: <iş> (position n)`. |
| `DrainStart(p)` | `sw_queue_start` (`src/lib/queue.sh`), `./softwary queue drain` içinde: koşu durmamışsa `sw_lock_try merge`. |
| `Pick(p)`, `RacyRelease(p)` | `sw_queue_next` (`src/lib/queue.sh`): durmuş koşu ya da boş kuyruk görülürse `merge` kilidi **aynı bölümde** bırakılır (`sw_lock_release merge`); aksi hâlde kuyruk başı alınır. |
| `Have(p)` | `sw_merge_one` (`src/lib/merge.sh`) başı: `gh pr view --json state`; `MERGED` ise koşullar hesaplanmaz, `gh pr merge` çağrılmaz. |
| `Sync(p)` | `sw_merge_conditions` 2. adım: `fetch`, gerekirse `git merge origin/<dal>`, `sw_job_push`. |
| `Verify(p)` | `sw_merge_conditions` 1. ve 3.–9. adımlar (`guard`, onaylar, dilim, `risk`, `verify`, PR, değerlendirme); tutmazsa `sw_merge_refuse` → `sw_merge_refuse_locked` (`escalate` olayı ve kuyruktan çıkarma tek bölüm). |
| `Dequeue(p)` | Kodda yoktur; yalnızca `splitdequeue` varyantında, refüzle kuyruktan çıkarmayı ayırır. |
| `StartMerge(p)`, `FinishMerge(p)` | `sw_merge_one` içindeki `gh pr merge --squash --match-head-commit <sha>` çağrısı (önce `merge_sha` iş dosyasına yazılır). |
| `PostCheck(p)` | `sw_queue_integration` (`src/lib/queue.sh`): uç ağacı birleşen SHA'nın ağacıysa ek denetim yok, değilse `sw_queue_verify` (`_integration` worktree'sinde tam `verify`); kırmızıysa `sw_queue_revert` ve `sw_queue_halt_locked`. |
| `Record(p)` | `sw_merge_record_locked` (`src/lib/merge.sh`): `merged` olayı, kuyruktan çıkarma, `decision.md`, ana checkout'un `pull`'u ve worktree'nin kaldırılması tek bölüm. |
| `Crash(p)` | `kill -9`: `EXIT` tuzağı çalışmaz, kilit kalır. Kırma: `sw_lock_probe`/`sw_lock_break` (`src/lib/lock.sh`). |
| `ExtPush`, `ExtFix` | Modelin dışındaki dünya: başkasının `origin`'e itmesi; insanın geri alma PR'ını birleştirmesi. |
| `Resume` | `sw_run_unhalt` (`src/lib/run.sh`), `run start` içinde. |

Modeldeki durumlar kodda şunlardır: `st[j]` iş dosyasının `state`'i, `queue` `.softwary/state/queue`, `lock` `.softwary/state/locks/merge/owner`, `halted` koşu dosyasındaki `halted=`.

## Sınırlar ve varsayımlar

- **Boyut:** 3 iş (`j1` ile `j2`'nin `touches`'ı kesişir), 2 süreç, `concurrency` 2, en fazla 1 çöküş, en fazla 1 dış push. İyi model 16.858 ayrık durum (39.627 üretilen), yaklaşık 5 saniye; `Concurrency = 3` ve `MaxPushes = 2` ile de geçer (36.715 durum, 7 saniye). Çöküş sayısı 2 yapılırsa iki süreç de ölür ve boşaltacak kimse kalmaz; bu modelin değil ortamın sınırıdır.
- **Atomiklik:** bir durum kilidi bölümü modelde tek eylemdir. Kodda bölümün ortasında `kill -9` yaşanırsa yarım yazım kalabilir; kod bunu yazma sırasıyla (önce kuyruğa ekle, sonra durumu değiştir; önce durumu değiştir, sonra kuyruktan çıkar) ve `sw_queue_next`'in onarımıyla (kuyrukta `approving` iş kuyruğa alınır, başka durumdaki iş kuyruktan düşer) karşılar; model bunu doğrulamaz.
- **`mkdir`:** kilit alma tek bölünmez adım kabul edilir. Ölü sahibin kilidini kırma `.breaking` dizini üzerinden sıraya sokulur (iki kırıcı aynı anda kırmaz, kırıcı sahibi yeniden okur), bu yüzden modelde `DrainStart`'ın bir parçasıdır. Bu, kodun testlerinde (`lock_test.sh`, 20 eşzamanlı `job tokens`) sınanır; modelde değildir.
- **`kill -0`:** sahibin ölü olup olmadığı yalnızca aynı makinede ve işlem kimliğiyle anlaşılır. İşlem kimliğinin başka bir süreç tarafından yeniden kullanılması (kimlik geri dönüşü) ve başka makine kapsam dışıdır; başka makinenin kilidi kırılmaz.
- **Doğrulama sonucu:** `Verify` yalnızca "eşitlenmiş ağaçta başkasının kötü commit'i var" ise başarısız olur. `verify`'ın kendi sonuçları (kararsız testler, bütçe, tur sınırı, `merge refused` nedenleri) modellenmez; hepsi `Escalate`/`Verify` reddi içinde tek sonuçtur.
- **Dışarıda kalanlar:** `job gate` öncesi aşamalar (`implementing`…`approving`) tek `work` durumudur; `resume`, `abandon`, token ve süre sınırları, birden çok orkestratör, birden çok makine, geri alma PR'ının içeriği (yalnızca "kırmızıysa koşu durur" modellenir) kapsam dışıdır.
- **`Progress`:** `merged`, `escalated` ya da `halted` hedeflerinden biri yeterlidir; durmuş koşu insanın sırasıdır ve `Resume` adil değildir. Adalet: `Begin`, kuyruğa ekleme, `DrainStart` ve bir sürecin kendi adımları zayıf adildir.
- **Belirtim ile kod arasındaki sapma** bu kilometre taşında elle bakımlıdır (V8'de bakımı otomatikleşir): bu dosyadaki eylem tablosu `src/lib/` fonksiyon adlarına işaret eder; bir fonksiyon adı ya da bölüm sınırı değişirse tablo ve model birlikte güncellenir.

## Varyant kaydı

Her varyantta `Bug` sabiti protokolün bir parçasını bozar ve yalnızca bozduğu özellik denetlenir (`merge-<ad>.cfg`). TLC'nin ilk ihlal satırı, bu makinedeki ilk çalıştırmanın üretilen/ayrık durum sayısı ve süresiyle:

| Varyant | Ne bozulur | Bozduğu özellik | TLC'nin ilk ihlal satırı | Durum (üretilen / ayrık), süre |
| --- | --- | --- | --- | --- |
| `nogate` | Eşitlemeden sonra `verify` yapılmadan birleştirilir | `GateBeforeMerge` | `Error: Invariant GateBeforeMerge is violated.` | 1.884 / 822, 1 s |
| `nooverlap` | Kabul `touches` kesişmesine bakmaz | `NoOverlap` | `Error: Invariant NoOverlap is violated.` | 21 / 16, 1 s |
| `nolock` | Boşaltıcı `merge` kilidini almaz | `SingleMerger` | `Error: Invariant SingleMerger is violated.` | 26.628 / 8.503, 2 s |
| `racyrelease` | Boş kuyruk görülür, kilit ayrı bir adımda bırakılır | `QueueOwned` | `Error: Invariant QueueOwned is violated.` | 8.050 / 3.680, 1 s |
| `nostale` | Ölü sahibin kilidi kırılmaz | `Progress` | `Error: Temporal property Progress was violated.` | 18.067 / 7.666, 4 s |
| `haltignored` | Durmuş koşuda boşaltıcı sürer | `NoMergeWhileHalted` | `Error: Invariant NoMergeWhileHalted is violated.` | 25.417 / 9.474, 1 s |
| `splitdequeue` | Refüzde olay ve kuyruktan çıkarma ayrı bölümlerde | `QueueKept` | `Error: Invariant QueueKept is violated.` | 1.819 / 788, 1 s |
| `norecover` | Birleşmiş PR'ın durumu sorulmaz | `MergedOnce` | `Error: Invariant MergedOnce is violated.` | 15.471 / 6.756, 2 s |

İyi model: `Model checking completed. No error has been found.` (39.627 / 16.858, 5 s). Durum sayıları TLC'nin çok işçili çalışmasında çalıştırmadan çalıştırmaya biraz değişir; ihlalin adı değişmez, `tests/formal_test.sh` onu sınar.
