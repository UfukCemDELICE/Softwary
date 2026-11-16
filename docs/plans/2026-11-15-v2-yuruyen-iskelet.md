# V2 Yürüyen iskelet — Uygulama planı

**Goal:** `docs/specs/V2.md`'deki AC-V2-01..17'yi karşılamak: ürün tanımı ve blueprint denetimleri, içerik özetli onaylar, bağımlılıklı plan ve otomatik spec onayı, `transitions.json` ile iş durumu, sıralı döngü (`run`, `job`), kendi koşullarını hesaplayan birleştirme scripti, `models.conf`, yeni skill ve ajanlar.

**Architecture:** Mevcut düzenin üstüne biner. Yeni kütüphane dosyaları: `src/lib/product.sh` (`product check`, `blueprint check`, özet, `approve`), `src/lib/data.jq` (veri modeli denetimi), `src/lib/plan.sh`, `src/lib/job.sh` (geçiş tablosu, `job`, bütçe, olay günlüğü), `src/lib/run.sh` (`run`, `merge`), `src/lib/transitions.json` (tek kaynak), `src/lib/loopconf.sh` (`loop.conf`, `models.conf`). Hepsi `src/bin/softwary`'den kaynaklanır; `help` yeni komutları listeler (skill testlerinin tek kaynağı).

**Tech Stack:** POSIX `sh`, `git`, `jq`, `gh` (yalnızca döngüde), `shellcheck`. Test düzeneği `tests/lib.sh` (`sh tests/run.sh`).

**Spec:** `docs/specs/V2.md` (approved). Bağlam: `docs/design.md` (v2), `docs/decisions.md` (D-01..D-64), `docs/sources.md`.

## Global Constraints

- Scriptler POSIX `sh`; ek bağımlılık yok (`gh` yalnızca `job pr|ci|merged` ve `merge` içinde çağrılır); `shellcheck -s sh` temiz.
- Çıkış kodları `0/1/2`; paket içeriği İngilizce, `docs/` Türkçe.
- Her test `test_` ile başlar, üstündeki yorum kriter kimliğini taşır (`# AC-V2-07`).
- Önce test yazılır, kırmızı görülür, sonra kod.
- Testler gerçek GitHub'a gitmez: sahte `gh` ve yerel bir `origin` (çıplak repo) kullanılır.
- Saat kancası yok (D-55): süre testleri iş ve koşu dosyalarındaki `started` değerini geçmişe yazar.
- Kararlar `docs/decisions.md`'ye "V2" başlığı altında D-65'ten başlayarak yazılır.
- Dal `claude/zen-ramanujan-jy9sc6`; PR yalnızca istenince açılır.

## Kararlar (decisions.md'ye girer)

- **D-65 Spec onayı:** V2 spec'i, kullanıcı "spec'i yaz, implemente ettir" dediği için yazıldığı oturumda `approved` yapıldı (D-42 ile aynı yol).
- **D-66 `PRODUCT.md` biçimi:** Zorunlu bölümler tam olarak `## Problem`, `## Users`, `## Scope`, `## Out of scope`, `## Features`, `## Non-functional requirements`, `## Constraints`, `## Success metrics`, `## Open questions`. Özellikler `## Features` altında `### F<n>: <ad>` (`n` ≥ 1, tekil). Örnekler o özelliğin alt bölümünde `- **EX-F<n>-NN:** <Given/When/Then>` maddeleridir; başka bir özelliğin alt bölümündeki `EX-F<m>-` kimliği önek hatasıdır, yinelenen kimlik hatadır. `## Open questions`'taki her madde bir sorundur. `UNSET` içeren her satır bir sorundur (şablon yer tutucuları `UNSET`'tir, açıklama yorumları bu sözcüğü içermez). Satır sonundaki `\r` atılır (D-48). Dosya yoksa 2. Şablon `src/templates/artifacts/PRODUCT.md`.
- **D-67 Blueprint biçimi:** CALM düğümünün `metadata.features`'ı isteğe bağlıdır; varsa `^F[1-9][0-9]*$` dizgelerinden oluşan boş olmayan bir dizidir (`model validate` denetler, `model.jq`). Veri modeli `architecture/data/model.json`: `{"entities":[{"id","name","fields":[{"name","type","required"?}],"relations"?:[{"to","kind"}]}]}`; `id` `^[a-z][a-z0-9_-]*$` ve tekil, alan adları varlık içinde tekil, `type` boş olmayan dizge, `kind` `one-to-one`, `one-to-many`, `many-to-one`, `many-to-many`'den biri, `to` var olan bir varlık. Denetim `src/lib/data.jq`'da, çıktı `<json yolu>: <sorun>`. `blueprint check`: `PRODUCT.md`, model ya da veri modeli yoksa 2; ürün denetimi geçmiyorsa tek satır `product/PRODUCT.md: product check fails`; sonra model doğrulama sorunları, veri modeli sorunları, hiçbir düğümde geçmeyen özellik (`feature F2 is not delivered by any component`) ve üründe olmayan özelliğe başvuran düğüm. Sözleşmelerin içeriği V2'de denetlenmez. Şablon `src/templates/artifacts/data-model.json`.
- **D-68 Onay özeti:** Kapsanan her dosya için `git hash-object`; `<blob> <yol>` satırları yola göre (`LC_ALL=C`) sıralanır ve bu metnin `git hash-object --stdin` özeti onaydır. Ürün: `product/PRODUCT.md`. Blueprint: `architecture/model/system.calm.json`, `architecture/data/model.json` ve `architecture/contracts/` altındaki her dosya (`find`, gizli dosyalar dahil). Kayıt `.softwary/config/approvals.conf`: `product = <özet>`, `blueprint = <özet>`; `commands.conf` ayrıştırıcısıyla okunur (bozuk satır, yinelenen ya da bilinmeyen anahtar `approvals.conf:<satır>: ...` ile 2). Dosyayı yalnızca `approve` yazar (başlık yorumuyla oluşturur, satırı değiştirir); `install.sh` ve `upgrade` dokunmaz. Durum: eşitse `approved`, farklıysa `stale`, satır yoksa `missing`. `approve blueprint` ürün onayı `approved` değilse 1. Olay günlüğüne `approve_product`/`approve_blueprint`, iş `-`, ayrıntı özet. Git deposu değilse 2.
- **D-69 Kriter ↔ örnek bağı:** `plan check`, durumu `draft` ya da `approved` olan her spec'te her kriter maddesinin (`- **AC-NNN-NN:**` satırı) en az bir `EX-F<n>-NN` kimliği taşımasını ve her kimliğin `PRODUCT.md`'de bulunmasını ister. `done` spec'ler denetlenmez. `trace` değişmez (v1 projeleri `PRODUCT.md`'siz çalışmaya devam eder). Spec şablonunun yorumu ve kriter örneği buna göre güncellenir.
- **D-70 Spec'ler arası bağımlılık ve iş kimliği:** Dilim `depends_on` girdisi `S<n>` (aynı spec) ya da `NNN-S<n>` (başka spec'in dilimi) olur; `trace` ikisini de kabul eder ve var olmayanı bildirir. İş kimliği `NNN-S<n>`. `plan check` döngüyü Kahn yöntemiyle bulur ve sıralanamayan dilimleri (döngüde olan ya da döngüye bağlı olanlar) sıralı olarak `dependency cycle among: 001-S1 001-S2` satırında yazar.
- **D-71 Analist kaydı ve otomatik onay:** `specs/NNN-ad/analysis.md`, üst bilgi `spec`, `digest`, `decision` (`pass` ya da `fail`); `digest`, spec `draft` iken `git hash-object specs/NNN-ad/spec.md` çıktısıdır. Şablon `src/templates/artifacts/analysis.md`. `plan approve <spec>` (kimlik ya da klasör): spec `draft` değilse, onaylar güncel değilse, `plan check` o spec için sorun bildiriyorsa, kayıt yoksa, `spec` uyuşmuyorsa, `decision` `pass` değilse ya da `digest` güncel spec'in özeti değilse nedenini söyleyip 1; aksi hâlde üst bilgideki `status: draft`'ı `status: approved` yapar ve `plan_approve` olayını yazar. `spec-analyst` yalnızca bu dosyayı yazar.
- **D-72 Geçiş tablosu:** `src/lib/transitions.json` tek kaynaktır: `states`, `terminal` ve `transitions` (`from`, `event`, `to`, isteğe bağlı `round: "next"|"reset"`). Durumlar `ready implementing gating pr ci reviewing approving merged escalated abandoned`; son durumlar `merged abandoned`. Geçişler: `ready start→implementing (next)`, `implementing implemented→gating`, `gating gate_pass→pr`, `gating gate_fail→implementing (next)`, `pr pr_opened→ci`, `ci ci_pass→reviewing`, `ci ci_fail→implementing (next)`, `reviewing review_approve→approving`, `reviewing review_changes→implementing (next)`, `approving merged→merged`, `implementing|gating|pr|ci|reviewing|approving escalate→escalated`, `escalated resume→implementing (reset)`, `escalated human_merged→merged`, `escalated abandon→abandoned`. `reset` turu 1'e ve işin `started`'ını şimdiye çeker (insan yeni bir hak tanıdı).
- **D-73 İş dosyaları ve olay günlüğü:** `.softwary/state/jobs/<iş>/job`, `anahtar=değer` satırları: `state`, `round`, `started` (`date +%s`), `tokens`, `branch`, `pr`. Escalate sorusu `escalation` dosyasında, approver kararı `decision.md`'de, danışman notu `advice.md`'de. Olay günlüğü `.softwary/state/events.log`, satır başına `jq -nc` ile bir JSON nesnesi: `time` (`date -u +%Y-%m-%dT%H:%M:%SZ`), `job`, `event`, `from`, `to`, `detail`. Durumu yalnızca `job.sh`'deki tek geçiş fonksiyonu yazar; `job event <iş> <olay> [ayrıntı]` onu dışarı açar (test ve orkestratör), diğer komutlar onu çağırır. Çıkış: uygulandı 0 (bütçe yüzünden escalate dahil, satır bunu söyler), tabloda yok 1 (durum ve günlük değişmez), bilinmeyen iş ya da kullanım 2. Sahte bir PASS kayıt ettirmek kazandırmaz, çünkü `merge` her koşulu yeniden hesaplar (İlke 6).
- **D-74 Sınırlar:** `.softwary/config/loop.conf` (projeye ait, `install.sh` yoksa kurar): `max_rounds = 3`, `max_job_minutes = 45`, `max_run_minutes = 240`, `concurrency = 1` (D-50), `max_job_tokens = UNSET`, `max_run_tokens = UNSET`. Değerler pozitif tam sayı; token anahtarları `NONE: <gerekçe>` de olabilir; `concurrency` 1'den farklıysa `concurrency above 1 arrives with parallel jobs (V4)`. Bütçe her `job event`'te `escalate`, `resume`, `abandon`, `human_merged` dışında denetlenir: işin dakikası, koşunun dakikası, iş ve koşu tokenları aşılmışsa olay uygulanmaz, iş `budget: <anahtar> <sınır>` ayrıntısıyla `escalated` olur. `round: next` geçişi turu `max_rounds`'un üstüne çıkaracaksa `round limit <n>` ile `escalated`. `job tokens <iş> <n>` işin ve koşunun toplamına ekler ve `tokens` olayını (durum değişmeden) günlüğe yazar. `doctor` her sorunu `loop.conf` satırında, `run start` 2 ile bildirir. Test düzeneği `setup_repo`'da token anahtarlarını doldurur (D-60 gibi).
- **D-75 Git ve GitHub:** Uzak ad sabit `origin`; iş dalı `softwary/<iş>`. `job start` entegrasyon dalında, temiz ağaçta (izlenmeyen dosya dahil), açık koşu varken ve `escalated` olmayan etkin iş yokken çalışır; `origin` varsa önce `git pull --ff-only origin <dal>`. Dosya değiştirmez: dilimi `in-progress` yapmak uygulayıcının işidir. `job gate` iş dalında temiz ağaç ister (yoksa 2, geçiş yok), tam `verify`'ı `--base origin/<dal>` ile çalıştırır ve çıktıyı `jobs/<iş>/gate-<tur>.log`'a yazar. `job pr` iter (`git push -u origin softwary/<iş>`), PR kayıtlı değilse `gh pr create --base <dal> --head softwary/<iş> --title "<iş>: <goal>" --body <spec ve dilim yolu>` çalıştırır ve çıktının son satırındaki URL'nin son parçasını PR numarası olarak kaydeder; kayıtlıysa yalnızca iter. `job ci`: `gh pr view <n> --json headRefOid --jq .headRefOid` yerel `HEAD`'e eşit değilse `ci_fail` (`PR head is not HEAD`); `gh pr checks <n> --watch` 0 ise `ci_pass`, değilse `ci_fail`. `job review`: dilimin inceleme kaydı `slice` ve `decision` (D-45) ile geçerli değilse 1; `approve`'da dilimin `status`'u `done` olur, kayıt ve dilim `<iş>: review approved` ile commit'lenip itilir; `changes`'te kayıt commit'lenip itilir. `job escalate <iş> <soru>`, `job resume <iş> <yanıt>`, `job abandon <iş> <gerekçe>`; `job merged <iş>` yalnızca `gh pr view <n> --json state --jq .state` `MERGED` ise `human_merged` uygular (R3 ya da reddedilen birleştirmeyi insan yapınca). `job show <iş>` dosyayı ve son olayları yazar.
- **D-76 Birleştirme scripti:** `merge <iş>`: iş `approving` değilse ya da `decision.md` `decision: merge` taşımıyorsa 1 (geçiş yok); iş dalında temiz ağaç değilse 2. Sonra sırasıyla, her biri tutmazsa `merge refused: <koşul>` ayrıntısıyla `escalated` ve `gh pr merge` hiç çağrılmaz: sınırlar; eşitleme (`git fetch origin <dal>`, `origin/<dal>` `HEAD`'in atası değilse `git merge --no-edit origin/<dal>`; çakışmada `git merge --abort` ve `conflict with <dal>`), `git push`; onayların güncelliği; dilimin `done` ve incelemesinin `approve` olması; `risk <spec> --base origin/<dal>` R3 değil; tam `verify --base origin/<dal>` (çıktı `jobs/<iş>/merge.log`); PR başı `HEAD` ve `gh pr checks <n> --watch` 0. Hepsi tutarsa `gh pr merge <n> --squash --match-head-commit <sha>`; başarısızsa `gh pr merge failed` ile escalate. Sonra `git checkout <dal>`, `git pull --ff-only origin <dal>`, `merged` olayı ve `decision.md`'nin sonuna `merged: <sha>` satırı.
- **D-77 Koşu:** `.softwary/state/run`: `started`, `tokens`, kapanınca `stopped`. `run start`: açık koşu varsa `run: resuming (started <zaman>)` ve 0, saat sıfırlanmaz; yoksa `loop.conf`/`models.conf` geçersizse 2, onay bayat ya da eksikse, `plan check` sorun bildiriyorsa 1, entegrasyon dalında ve temiz değilse 2; geçerse kaydı açar, `run_start` olayı. `run next`: açık koşu yoksa 2; koşu sınırı aşılmışsa `stop: run limit (<anahtar>)` ve 1; son ya da `escalated` olmayan bir iş varsa `resume <iş> <durum>`; yoksa sıradaki hazır dilim (spec numarası, sonra dilim numarası sırasıyla; spec `approved`, dilim `planned`, bütün bağımlılıkları çalışma ağacında `done`, iş dizini yok) için `start <iş>`; yoksa `escalated` işler varsa `waiting: <işler>`; yoksa `none`. `run stop` `stopped` yazar, `run_stop` olayı.
- **D-78 `models.conf`:** `.softwary/config/models.conf` (projeye ait, `install.sh` yoksa kurar): `spec-analyst = opus`, `implementer = sonnet`, `advisor = opus`, `reviewer = opus`, `approver = opus` (D-50). Anahtarlar kurulu (yönetilen ve `local/`) subagent adlarıdır; değer `^[A-Za-z0-9._-]+$`. `doctor` `models` satırlarında: dosya yok, bozuk ya da yinelenen satır, ajanı olmayan anahtar, anahtarı olmayan ajan, geçersiz değer, `reviewer` ya da `approver`'ın `implementer` ile aynı değeri. `sync` dosya geçerliyse Claude Code subagent'larının üst bilgisine `description`'dan sonra `model: <değer>` yazar (hazırlık aşamasında üst bilgiye eklenir; Cursor ve Codex hedefleri satırı atar, V9); dosya yoksa ya da geçersizse `model` yazmaz ve bunu `doctor`'a bırakır (sync'i kilitlemez).
- **D-79 Ajan sözleşmesi:** Her ajan tek satır yanıt verir. `implementer`: `done`, `blocked: <neden>` ya da `advice: <soru>`; işini iş dalında commit'ler. `reviewer`: `approve` ya da `changes`. `approver`: `decision.md`'yi yazar, `./softwary merge <iş>` ya da `./softwary job escalate <iş> <soru>` çağırır, `merged` ya da `escalated: <soru>` döner. `advisor`: kod yazmaz, yalnızca `.softwary/state/jobs/<iş>/advice.md` yazar, `advice written` döner. `spec-analyst`: `analysis.md`'yi yazar, `pass` ya da `fail` döner. Claude Code'da subagent başka subagent çağıramadığı için danışmanı orkestratör çağırır ve `advice.md`'yi uygulayıcının sonraki çağrısına verir. Şablon `src/templates/artifacts/decision.md`.
- **D-80 Skill'ler:** v1'in altı aşama skill'i elle yürütülen yol olarak kalır (birleştirme V5'te). Yeni: `define` (birer birer soru, `PRODUCT.md` ve `CONTEXT.md`, `product check`, onayı insan verir), `blueprint` (`features`'lı model, veri modeli, gerekirse sözleşme, `proposed` ADR, `blueprint check`, onayı insan verir), `plan` (özellik başına spec, `EX-` bağları, `depends_on`/`touches`'lı dilimler, `spec-analyst`, `plan approve`, ardından insanın birleştireceği temel PR'ı: ürün, blueprint, ADR ve plan tek PR'da), `run` (orkestratör: yalnızca `run`, `job`, `status` komutlarını çalıştırır ve ajanları çağırır; yapıt ve durum dosyası yazmaz). `setup` boş repoda sonraki adımı `define` ve `blueprint` olarak söyler ve token sınırlarını sorar. `core.md`'ye kural: `./softwary approve`'u yalnızca insan çalıştırır.
- **D-81 Durum kodunun boyutu:** design §8'e göre `job.sh`, `run.sh` ve `plan.sh`'nin toplamı yaklaşık 500 satırı geçerse dil değiştirilmez; durum raporda satır sayısıyla insana açık soru olarak verilir.
- **D-82 Test düzeneği:** `tests/lib.sh`'ye: `add_origin` (`$T/origin.git` çıplak repo, `main` itilir), `fake_gh` (`$T/bin/gh`; çağrıları `$T/gh.log`'a yazar; `pr create` `https://github.com/o/r/pull/<n>` basar ve başlığı `$T/gh/pr-<n>`'e kaydeder; `pr view --json headRefOid` `$T/gh/head` dosyası varsa onu, yoksa `origin`'deki dalın ucunu; `pr view --json state` `$T/gh/state` ya da `OPEN`; `pr checks` `$T/gh/checks` dosyasındaki çıkış kodunu (varsayılan 0); `pr merge`, `$T/gh/merge` varsa onun çıkış kodunu, yoksa geçici bir klonda dalı `--squash` ile `main`'e birleştirip `origin`'e iter), `add_product`, `add_blueprint`, `add_plan` (fikstürler `tests/fixtures/artifacts/v2/`), `loop_conf` (token anahtarları dahil). `setup_repo` `loop.conf`'u doldurur. Güncellenen eski testler PR'da listelenir.

## Review Focus

1. `job event`'in bütçe denetimi `escalate`'in kendisini engellemez; `escalated`'dan `resume` sınırı aşan işte de çalışır (T5).
2. `merge`'de eşitleme commit'i oluşursa `verify` ve CI yeni SHA üzerinde çalışır; PR başı eski SHA ise reddedilir (T6).
3. `plan approve` spec'i değiştirdikten sonra `analysis.md`'nin özeti artık uymaz; bu beklenen durumdur, `plan check` analist kaydını denetlemez (T3).
4. `approve`, özet hesaplanırken değişmiş ama commit'lenmemiş dosyayı içeriğiyle sayar (çalışma ağacı) (T2).
5. `run next` `abandoned` bir işin dilimini yeniden başlatmaz (iş dizini var) (T7).
6. Eski kurulumlarda `models.conf` yokken `sync` çalışmaya devam eder (T4).

---

### Task 1: Ürün ve blueprint denetimleri (AC-V2-01, AC-V2-02)

**Files:** Create `src/lib/product.sh`, `src/lib/data.jq`, `src/templates/artifacts/PRODUCT.md`, `src/templates/artifacts/data-model.json`, `tests/product_test.sh`, `tests/blueprint_test.sh`, fikstürler `tests/fixtures/artifacts/v2/`. Modify `src/lib/model.jq` (`features`), `src/bin/softwary` (`product`, `blueprint`, `help`).

- [ ] `test_ac_v2_01_missing_product_exits_2`
- [ ] `test_ac_v2_01_valid_product_passes`: fikstür ürün 0.
- [ ] `test_ac_v2_01_each_missing_section`: dokuz bölümün her biri silinince adıyla bir satır, 1.
- [ ] `test_ac_v2_01_feature_without_example`, `test_ac_v2_01_wrong_prefix_and_duplicate`, `test_ac_v2_01_unset_and_open_questions`, `test_ac_v2_01_template_fails`: şablonun kendisi `UNSET`'ler yüzünden 1.
- [ ] `test_ac_v2_02_missing_inputs_exit_2`: ürün, model, veri modeli ayrı ayrı.
- [ ] `test_ac_v2_02_valid_blueprint_passes`.
- [ ] `test_ac_v2_02_data_model_problems`: yinelenen varlık, yinelenen alan, türsüz alan, bilinmeyen `to`, geçersiz `kind` her biri ayrı satır.
- [ ] `test_ac_v2_02_feature_coverage`: hiçbir düğümde olmayan özellik ve üründe olmayan özelliğe başvuru; `model validate` `features: ["x"]`'i reddeder.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 2: Onaylar (AC-V2-03, AC-V2-04'ün onay kısmı)

**Files:** Modify `src/lib/product.sh` (`sw_digest`, `sw_approval_state`, `sw_approve`), `src/lib/trace.sh` (`status`'a onay satırları), `src/bin/softwary` (`approve`). Test: `tests/approve_test.sh`.

- [ ] `test_ac_v2_03_approve_product_writes_digest`: `approvals.conf`'ta `product = <hex>`, olay günlüğünde `approve_product`.
- [ ] `test_ac_v2_03_failing_check_writes_nothing`: ürün denetimi başarısız → 1, dosya yok.
- [ ] `test_ac_v2_03_blueprint_requires_current_product`: ürün onayı yok ya da bayat → 1.
- [ ] `test_ac_v2_03_stale_on_change_add_remove`: `PRODUCT.md` değişince, sözleşme eklenince ve silinince, model ve veri modeli değişince `status` `stale`; yeniden onay `approved`.
- [ ] `test_ac_v2_03_bad_approvals_conf_exits_2`.
- [ ] `test_ac_v2_04_status_shows_approvals`: `missing`, `approved`, `stale`.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 3: Plan (AC-V2-05, AC-V2-06)

**Files:** Create `src/lib/plan.sh`, `src/templates/artifacts/analysis.md`, `tests/plan_test.sh`. Modify `src/lib/trace.sh` (`NNN-S<n>` bağımlılık), `src/templates/artifacts/spec.md` (`EX-` bağı), `src/bin/softwary`.

- [ ] `test_ac_v2_05_clean_plan_passes`.
- [ ] `test_ac_v2_05_approvals_required`: eksik ve bayat onay ayrı satırlar.
- [ ] `test_ac_v2_05_criterion_example_links`: örneksiz kriter, bilinmeyen örnek; `done` spec denetlenmez.
- [ ] `test_ac_v2_05_cross_spec_dependency`: `002-S1`'in `001-S2`'ye bağımlılığı geçerli; `001-S9` bilinmeyen (`trace` de bildirir).
- [ ] `test_ac_v2_05_cycle_lists_members`.
- [ ] `test_ac_v2_05_includes_trace`: `trace` sorunu `plan check`'i 1 yapar.
- [ ] `test_ac_v2_06_plan_approve_happy_path`: `status: approved`, olay günlüğünde `plan_approve`.
- [ ] `test_ac_v2_06_refusals`: spec `draft` değil, kayıt yok, `decision: fail`, eski `digest`, `spec` uyuşmuyor, `plan check` sorunu: her biri 1 ve spec değişmez.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 4: `loop.conf`, `models.conf`, `doctor` ve `sync` (AC-V2-11'in yapılandırma kısmı, AC-V2-14)

**Files:** Create `src/lib/loopconf.sh`, `src/templates/loop.conf`, `src/templates/models.conf`, `tests/models_test.sh`. Modify `install.sh` (`owned`), `src/lib/doctor.sh`, `src/lib/sync.sh` (hazırlıkta `model`), `src/targets/cursor.sh`, `src/targets/codex.sh` (satırı atar), `tests/lib.sh` (`loop_conf`, `setup_repo`).

- [ ] `test_ac_v2_11_loop_conf_validation`: sıfır, negatif, sayı olmayan, `concurrency = 2`, `UNSET` token; `doctor` satır numarasıyla, kurulumdan gelen şablon token yüzünden FAIL.
- [ ] `test_ac_v2_14_sync_writes_model`: `.claude/agents/implementer.md`'de `model: sonnet`, `reviewer.md`'de `model: opus`; Cursor ve Codex çıktısında `model` yok; `sync --check` 0.
- [ ] `test_ac_v2_14_doctor_models_problems`: eksik anahtar, fazla anahtar, geçersiz değer, `reviewer = sonnet` (implementer ile aynı) ayrı satırlar.
- [ ] `test_ac_v2_14_missing_models_conf_keeps_sync`: dosya silinince `sync` 0, `model` satırı yok, `doctor` FAIL.
- [ ] `test_ac_v2_14_install_keeps_owned_files`: `install.sh` ve `upgrade` var olan `loop.conf`/`models.conf`'u ezmez.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 5: Geçiş tablosu, `job` ve bütçe (AC-V2-07, AC-V2-08, AC-V2-11)

**Files:** Create `src/lib/transitions.json`, `src/lib/job.sh`, `tests/transitions_test.sh`, `tests/job_test.sh`. Modify `src/bin/softwary`, `tests/lib.sh` (`add_origin`).

- [ ] `test_ac_v2_07_table_is_well_formed`: her `from`/`to` `states`'te, son durumdan geçiş yok, (`from`, `event`) çiftleri tekil.
- [ ] `test_ac_v2_07_every_pair`: tablodaki bütün durumlar × tablodaki bütün olaylar; iş dosyası her denemede o duruma yazılır; tablodaki çift: yeni durum ve günlükte tek yeni satır (alanlar doğru); tablodaki olmayan: 1, durum ve günlük aynı.
- [ ] `test_ac_v2_07_unknown_job_exits_2`.
- [ ] `test_ac_v2_08_start_refusals`: dilim `planned` değil, spec `draft`, bağımlılık `done` değil, onay bayat, kirli ağaç, entegrasyon dalında değil, koşu yok, etkin başka iş var; her biri nedenini söyler, dal açılmaz.
- [ ] `test_ac_v2_08_start_opens_branch`: `softwary/001-S1`, durum `implementing`, tur 1; `escalated` bir iş başlamayı engellemez.
- [ ] `test_ac_v2_08_gate_pass_fail_flaky`: `test` komutu geçen, hep kalan ve bir kalıp bir geçen (sayaç dosyasıyla) üç durum; kirli ağaçta 2.
- [ ] `test_ac_v2_11_round_limit`: üçüncü `gate_fail`'den sonraki tur yerine `escalated`, ayrıntı `round limit 3`.
- [ ] `test_ac_v2_11_time_and_token_limits`: `started` geçmişe yazılınca iş ve koşu dakikası; `job tokens` ile iş ve koşu tokenı; her biri `escalated` ve aşılan anahtar.
- [ ] `test_ac_v2_11_escalate_resume_unaffected_by_budget` (Review Focus 1).
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 6: PR, CI, inceleme ve birleştirme (AC-V2-09, AC-V2-10, AC-V2-12)

**Files:** Modify `src/lib/job.sh` (`pr`, `ci`, `review`, `escalate`, `resume`, `abandon`, `merged`, `show`). Create `src/lib/run.sh` (`merge`), `src/templates/artifacts/decision.md`, `tests/merge_test.sh`, `tests/job_github_test.sh`. Modify `tests/lib.sh` (`fake_gh`).

- [ ] `test_ac_v2_09_pr_pushes_and_records`: `origin`'de dal, `gh.log`'da `pr create --base main --head softwary/001-S1`, PR numarası kayıtlı; ikinci `job pr` yeni PR açmaz.
- [ ] `test_ac_v2_09_ci_pass_fail_head_mismatch`.
- [ ] `test_ac_v2_10_review_missing_invalid`, `test_ac_v2_10_review_approve_commits_done`, `test_ac_v2_10_review_changes_new_round`.
- [ ] `test_ac_v2_12_merge_happy_path`: `gh.log`'da `pr merge <n> --squash --match-head-commit <sha>`, entegrasyon dalı güncel ve dilim `done`, `decision.md`'de `merged:`.
- [ ] `test_ac_v2_12_merge_preconditions`: `approving` değil, `decision.md` yok ya da `escalate`: 1; kirli ağaç 2.
- [ ] `test_ac_v2_12_each_refusal`: bütçe, çakışma, bayat onay, onaylamayan inceleme, R3, kırmızı `verify`, PR başı farklı, CI kırmızı, `gh pr merge` başarısız: her biri `escalated`, ayrıntıda koşul, `gh.log`'da `pr merge` yok (sonuncuda var ama durum `escalated`).
- [ ] `test_ac_v2_12_sync_creates_new_sha` (Review Focus 2): entegrasyon dalı ilerledikten sonra eşitleme commit'i, `verify` ve CI yeni SHA'da.
- [ ] `test_ac_v2_08_human_merged_and_abandon`: `job merged` yalnızca `MERGED`'de.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 7: Koşu ve `status` (AC-V2-13, AC-V2-04)

**Files:** Modify `src/lib/run.sh`, `src/lib/trace.sh` (`status`: işler ve insanı bekleyenler). Test: `tests/run_test.sh`, `tests/status_test.sh`.

- [ ] `test_ac_v2_13_start_refusals`: bayat onay, `plan check` sorunu, geçersiz `loop.conf`, kirli ağaç, yanlış dal.
- [ ] `test_ac_v2_13_start_and_resume`: ikinci `run start` `resuming`, `started` değişmez.
- [ ] `test_ac_v2_13_next_order`: yarım iş önce; sonra bağımlılık sırasıyla hazır dilim; `abandoned` dilim tekrar seçilmez; `escalated` iş varken `waiting:`; hiçbiri yoksa `none`.
- [ ] `test_ac_v2_13_next_stop_on_run_limit`.
- [ ] `test_ac_v2_04_status_jobs_and_escalations`: iş satırı (durum, tur, dakika), `escalated` bölümü soruyla; işsiz repoda eski çıktı değişmez.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 8: Skill'ler ve ajanlar (AC-V2-15)

**Files:** Create `src/skills/{define,blueprint,plan,run}/SKILL.md`, `src/agents/{approver,advisor}.md`. Modify `src/agents/{spec-analyst,implementer,reviewer}.md`, `src/skills/setup/SKILL.md`, `src/rules/core.md`. Test: `tests/skill_test.sh`.

- [ ] `test_ac_v2_15_distributed_and_short`: dört skill ve iki ajan üç araçta; her biri ≤ 80 satır; anılan her `./softwary` komutu `help`'te.
- [ ] `test_ac_v2_15_human_approves`: `define` ve `blueprint` `./softwary approve`'u insanın çalıştırdığını söyler; `core.md` kuralı.
- [ ] `test_ac_v2_15_run_contract`: `run` `job`, `merge` değil `approver`, tek satır yanıt, danışmanı orkestratörün çağırması, yapıt ve durum dosyası yazmama.
- [ ] `test_ac_v2_15_agent_files`: `approver` yalnızca `decision.md`, `merge`/`job escalate`; `advisor` yalnızca `advice.md`; `spec-analyst` yalnızca `analysis.md`; `implementer` tek satır yanıt ve commit.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 9: Uçtan uca ve bütünleşme (AC-V2-16, AC-V2-17)

- [ ] `tests/loop_e2e_test.sh` `test_ac_v2_16_empty_repo_to_two_merged_slices`: boş repo → fikstür ürün, `approve product`, blueprint ve kabul edilmiş ADR, `approve blueprint`, iki dilimli plan (`S2` `S1`'e bağlı), analist kayıtları, `plan approve`, temel commit ve `origin`'e itme → `run start` → her dilim için `run next`, `job start`, uygulayıcı yerine test kodu ve commit, `job event implemented`, `job gate`, `job pr`, `job ci`, inceleme kaydı, `job review`, `decision.md`, `merge` → `run next` `none`; entegrasyon dalında iki dilim `done`; olay günlüğündeki olay dizisi beklenenle aynı.
- [ ] `sh tests/run.sh` tam çıktı; `shellcheck -s sh -x install.sh src/bin/softwary src/lib/*.sh src/targets/*.sh src/hooks/* src/templates/softwary tests/*.sh` temiz.
- [ ] Mutasyon denetimi: geçiş tablosundan bir satır silme, bütçe karşılaştırması, `merge`'deki R3 ve CI denetimi, özetten bir dosyayı çıkarma; her biri sed ile bozulup testin kızardığı görülür, sonra geri alınır.
- [ ] `wc -l src/lib/job.sh src/lib/run.sh src/lib/plan.sh` (D-81).
- [ ] `docs/decisions.md`'ye D-65..D-82; `docs/roadmap.md`'de V2 durum notu; `docs/sources.md`'de V2'de uygulanan fikirlerin durumu.
- [ ] Güncellenen eski testler ve gerekçeleri listelenir; AC → test tablosu raporlanır.

## AC → test eşlemesi

| AC | Testler |
| --- | --- |
| AC-V2-01 | `product_test.sh` |
| AC-V2-02 | `blueprint_test.sh` |
| AC-V2-03 | `approve_test.sh` |
| AC-V2-04 | `approve_test.sh`, `status_test.sh` |
| AC-V2-05, 06 | `plan_test.sh` |
| AC-V2-07 | `transitions_test.sh` |
| AC-V2-08 | `job_test.sh`, `job_github_test.sh` |
| AC-V2-09, 10 | `job_github_test.sh` |
| AC-V2-11 | `models_test.sh` (yapılandırma), `job_test.sh` (sınırlar) |
| AC-V2-12 | `merge_test.sh` |
| AC-V2-13 | `run_test.sh` |
| AC-V2-14 | `models_test.sh` |
| AC-V2-15 | `skill_test.sh` |
| AC-V2-16 | `loop_e2e_test.sh` |
| AC-V2-17 | `sh tests/run.sh` + `shellcheck` + güncellenen test listesi |
