# V3 Güveni sertleştirme — Uygulama planı

**Goal:** `docs/specs/V3.md`'deki AC-V3-01..14'ü karşılamak: `guard` (korunan yollar, `touches`, test gevşetme), onun `job gate` ve `merge`'e bağlanması, `touches` denetimi, diff'ten hesaplanan R3, bozuk diff'lerle değerlendirme (`eval prepare|score`, `eval.conf`) ve otomatik birleştirme eşiği, bahane tabloları ve kanıtlı inceleme.

**Architecture:** Yeni mantık iki yeni dosyada: `src/lib/guard.sh` (`sw_guard JOB BASE`, ihlalleri satır satır basar) ve `src/lib/eval.sh` (`prepare`, `score`, `sw_eval_state`). Değerlendirme yapıtları `src/eval/` altında (`sample/`, `cases/NN-ad/`) ve `install.sh` ile `.softwary/eval/`'a yönetilen ağaç olarak kurulur. `job.sh` ve `run.sh`'ye yalnızca çağrı eklenir (D-81).

**Tech Stack:** POSIX `sh`, `git`, `jq`, `shellcheck`. Test düzeneği `tests/lib.sh` (`sh tests/run.sh`).

**Spec:** `docs/specs/V3.md` (approved). Bağlam: `docs/design.md` §4 ve §7, `docs/decisions.md` (D-65..D-82), `docs/sources.md`.

## Global Constraints

- Scriptler POSIX `sh`; ek bağımlılık yok; `shellcheck -s sh -x` temiz.
- Çıkış kodları `0/1/2`; paket içeriği İngilizce, `docs/` Türkçe.
- Her test `test_` ile başlar, üstündeki yorum kriter kimliğini taşır.
- Önce test, kırmızı, sonra kod.
- Paket içeriği stack'e özgü sözcük denetiminden geçer (AC-M0-09): örnek proje POSIX `sh` ile yazılır; `test-skip.conf` şablonunda çatı adı geçmez.
- Kararlar `docs/decisions.md`'ye "V3" başlığı altında D-83'ten başlayarak yazılır.
- Dal `claude/zen-ramanujan-jy9sc6`; push ve PR'ı orkestratör yapar.

## Kararlar (decisions.md'ye girer)

- **D-83 Spec onayı:** V3 spec'i kullanıcı isteğiyle yazıldığı oturumda `approved` yapıldı (D-42, D-65).
- **D-84 `guard` komutu:** `guard <iş> [--base <ref>]`; iş `NNN-S<n>` (iş dizini gerekmez: dilim dosyası yeterli, böylece inceleyici ve testler de kullanır). Taban verilmezse `sw_default_base`. Değişiklik kümesi `git diff --no-renames --name-only <merge-base>..HEAD` (yalnızca commit'lenmiş; döngü temiz ağaçta çalışır). Çıktı: ihlal başına `guard: <tür>: <ayrıntı>` (türler `protected`, `outside touches`, `test deleted`, `criterion dropped`, `skip marker`), sonra `guard: N problem(s)` ya da `guard: no problems`. İhlal 1; kullanım, bilinmeyen dilim, taban, `test_paths`, `test-skip.conf` 2.
- **D-85 Korunan yollar:** Pakette sabit liste (`SW_PROTECTED`): `.softwary/`, `.github/`, `CODEOWNERS`, `docs/CODEOWNERS`, `softwary`, `product/`, `architecture/model/`, `architecture/data/`, `architecture/contracts/`. Dizin girdisi altındaki her yolu kapsar. Liste projede genişletilemez ya da daraltılamaz (genişletme V5'te `architecture/formal/` ile gelir). Üretilen araç dosyaları (`.claude/` vb.) listede değildir: kaynakları `.softwary/` altında korunur ve `sync --check` sapmayı `verify`'da yakalar.
- **D-86 `touches` eşleşmesi:** Girdi glob karakteri (`*?[`) taşıyorsa `risk.conf`'taki gibi `case` deseni (`*` `/`'yi de kapsar); taşımıyorsa yola eşit ya da yolun üst dizini (sondaki `/` isteğe bağlı). İşin `specs/<dizin>/slices/S<n>.md` ve `specs/<dizin>/reviews/S<n>.md` dosyaları her zaman kapsanır. `plan check`: `draft`/`approved` spec'in dilimlerinde `touches` boşsa `touches is empty`, girdi `/` ile başlıyor ya da `..` parçası taşıyorsa `touches: '<g>' is outside the repository`.
- **D-87 Test gevşetme:** `test_paths` (ayar, boşlukla ayrılmış) altında: (a) diff'te silinen dosya `test deleted`; (b) tabandaki (`git grep -h -o -E 'AC-[A-Z0-9]+-[0-9]{2}' <merge-base> -- <test_paths>`) kimliklerden `HEAD`'de geçmeyen her biri `criterion dropped`; (c) `git diff -U0 <merge-base>..HEAD -- <test_paths>`'in `+` ile başlayan (`+++` olmayan) satırlarından `test-skip.conf`'taki bir ERE'ye uyan her biri `skip marker: <yol>: <satır>`. Yeniden adlandırma silme sayılır (escalate edilir; insan karar verir).
- **D-88 `test-skip.conf`:** `.softwary/config/test-skip.conf`, projeye ait (`owned`). Yorum ve boş satır dışındaki her satır bir ERE'dir (`grep -E` ile derlenemeyen satır `test-skip.conf:<satır>: invalid pattern`), ya da dosyanın tek satırı `NONE: <gerekçe>`. Şablonda yalnızca yorum vardır; desen yoksa `doctor` `test-skip FAIL (no patterns: add your test framework's skip and focus markers, or NONE: <reason>)` ve `guard` 2. `setup_repo` bir desen yazar; listelenir.
- **D-89 Kapıda ve birleştirmede `guard`:** `job gate`: `verify`'dan önce `guard --base origin/<dal>`; ihlalde çıktı `gate-<tur>.log`'a, `gate_fail` ayrıntısı `guard: <ilk ihlal>`; yeniden deneme yok (deterministik). `merge`: eşitleme ve push'tan hemen sonra, onaylardan ve `verify`'dan önce `guard`; ihlalde `merge refused: guard: <ilk ihlal> (+N more)` ve `escalated`. Korunan yol denetimi `verify`'dan önce geldiği için birleştirilen SHA'daki `.softwary/` ve yapılandırma entegrasyon dalınınkiyle aynıdır: kapı entegrasyon dalının denetimleriyle çalışır (design §4, `docs/sources.md` zazencodes). `guard` 2 verirse (yapılandırma) `merge` escalate eder, `job gate` 2 döner.
- **D-90 Diff'ten R3:** `merge`'deki risk denetimi `risk <spec> --base origin/<dal>` çıktısının kademesidir; `risk` zaten değişen yolların `risk.conf` kademesini hesaplar (D-30). V3 bunu spec'i R1 olan ama R3 yola dokunan iş için testle sabitler; davranış gerekirse düzeltilir.
- **D-91 Değerlendirme yapıtları:** `src/eval/sample/`: POSIX `sh` ile yazılmış küçük bir proje (`src/`, `tests/run.sh` kriter kimlikli testler, `product/`, `architecture/`, `specs/001-*/spec.md` `approved` ve `slices/S1.md` `in-progress`, `.softwary-config/` altında `commands.conf`, `risk.conf`, `tools.conf`, `waivers.conf`, `loop.conf`, `models.conf`, `test-skip.conf`). `src/eval/cases/NN-ad/`: `diff.patch` (örneğe `git apply` ile uygulanır; dilimi `review` yapar), `expect` (`approve` ya da `changes`), `kind` (`clean`, `guard` ya da `review`). En az 10 vaka (AC-V3-10). `install.sh` `eval` ağacını yönetilen olarak kurar ve `upgrade` budar.
- **D-92 `eval prepare <dizin>`:** Dizin yoksa oluşturur; boş değilse 2. Vakalar `case-01..case-NN` olarak adlandırılır; sıra vaka adının `printf '%s' <ad> | git hash-object --stdin` özetine göredir (deterministik, ama ad sırası türü açığa vurmaz). Her vaka: örnek proje + kurulu softwary (`$SOFTWARY_HOME`'dan `bin lib rules targets skills agents hooks templates`, sarmalayıcı, `.softwary-config/` → `.softwary/config/`), `sync`, `main`'de commit; `review` dalında yama uygulanıp commit. `expect` ve `kind` vaka reposuna kopyalanmaz. Eşleme `.softwary/state/eval/map` (`case-NN <vaka-adı>`) ve dizin yolu `.softwary/state/eval/dir`. Çıktı, inceleyicinin her vakada çalışacağı yolları listeler.
- **D-93 `eval score <dizin>`:** Eşleme yoksa ya da dizin uyuşmuyorsa 2. Her vaka için `review` dalında `guard S1 --base main` (vaka reposunda kendi `./softwary`'siyle) ve `specs/001-*/reviews/S1.md`'nin `decision`'ı. Bozuk vaka (`expect: changes`) `guard` 1 ya da `decision: changes` ise yakalanmıştır; temiz vaka `decision: changes` ise yanlış alarmdır. Kaydı olmayan ya da `decision`'ı geçersiz vaka varsa hepsi listelenir, 1, hiçbir şey yazılmaz. Aksi hâlde `.softwary/config/eval.conf`: `caught`, `broken`, `false_alarms`, `clean`, `digest`, `date` (`commands.conf` ayrıştırıcısıyla okunur) ve tablo basılır. `digest`: `.softwary/agents/reviewer.md`, varsa `.softwary/local/agents/reviewer.md` ve `models.conf`'taki `reviewer` değeri üzerinden D-68 yöntemiyle.
- **D-94 Otomatik birleştirme eşiği:** `loop.conf` `min_catch_percent` (0–100 tam sayı; şablonda `90`, **insan kararı bekler**). `sw_eval_state`: `missing`, `stale` (özet uyuşmuyor), `below <yüzde>` ya da `ok <yüzde>`; yüzde `caught*100/broken` (tam sayı bölme). `merge` bütün koşullardan sonra, `gh pr merge`'den hemen önce denetler; `ok` değilse `merge refused: auto-merge is off (evaluation <durum>); merge the PR yourself and run ./softwary job merged <iş>`. `status` `evaluation: ...` satırını yalnızca `loop.conf` varsa yazar. Değerlendirmenin kendisi bir insan eylemidir (skill çalıştırılır, `eval.conf` korunan yolda olduğu için bir iş onu değiştiremez).
- **D-95 Skill ve ajan metinleri:** `implement`, `implementer`, `run`: `## Excuses` başlığı altında en az üç satırlık tablo (ör. "Test bozuk, atlarım" → "Testi atlamak gevşetmedir; dur ve sor"). `reviewer` ve `review.md` şablonu: her bulgu `- <yol>:<satır> — <sorun> — evidence: <komut ve çıktısı ya da alıntı>`; kanıtı olmayan bulgu yazılmaz; `./softwary guard <iş>` çıktısı incelemeye girer. Yeni `evaluate` skill'i: `eval prepare`, her `case-NN` için temiz bağlamlı `reviewer` (taban `main`, dilim `S1`, yalnızca o dizinde), `eval score`, sonucu ve `eval.conf`'u commit'lemesini insana bırakır. `setup`: `test-skip.conf` ve `min_catch_percent`. `core.md`: kural 3'ün yanına "korunan yollara döngüde dokunulmaz".
- **D-96 Test düzeneği:** `setup_repo` `test-skip.conf`'a bir desen yazar; `add_eval` geçerli bir `eval.conf` yazar (özet güncel, `caught = broken`). V2'nin birleştirmeye giden testleri (`merge_test.sh`, `loop_e2e_test.sh`) `add_eval` ile güncellenir ve listelenir; ayrıca bir iş dalının `touches` dışına çıkan fikstür yolları varsa `touches` düzeltilir ve listelenir.

## Review Focus

1. Eşitleme commit'i entegrasyon dalından gelen yolları içerir; `guard` ortak atadan `HEAD`'e baktığı için, eşitlemeden sonra ortak ata entegrasyonun ucudur ve bu yollar diff'e girmez (T3).
2. `guard`'da `test_paths` birden çok dizin olabilir; `git grep` ve `git diff` yol listesini doğru alır (T2).
3. `eval prepare` vaka reposunda ana reponun `state/`'ini ya da `eval.conf`'unu taşımaz (T4).
4. `eval score`'un `guard` çağrısı vaka reposunun kendi kurulumuyla çalışır; ana reponun `SOFTWARY_ROOT`'u sızmaz (T4).
5. `min_catch_percent = 0` değerlendirme `ok` için yine `eval.conf` ister (T5).

---

### Task 1: Korunan yollar ve `touches` (AC-V3-01, 02, 04'ün bir kısmı, 07)

**Files:** Create `src/lib/guard.sh`, `tests/guard_test.sh`. Modify `src/bin/softwary` (`guard`, `help`), `src/lib/plan.sh` (`touches`).

- [ ] `test_ac_v3_01_protected_paths`: her korunan kökten bir dosya ayrı satır; `src/` değişikliği satır üretmez; 1 ve 0.
- [ ] `test_ac_v3_02_outside_touches`: tam yol, dizin, glob girdileri; dilim ve inceleme dosyası kapsanır; kapsanmayan yol satırı.
- [ ] `test_ac_v3_04_usage_and_config_errors`: bilinmeyen dilim, taban yok: 2.
- [ ] `test_ac_v3_07_plan_check_touches`: boş, `/abs`, `a/../b`.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 2: Test gevşetme ve `test-skip.conf` (AC-V3-03, 04)

**Files:** Modify `src/lib/guard.sh`, `src/lib/doctor.sh`, `install.sh` (`owned`). Create `src/templates/test-skip.conf`. Modify `tests/lib.sh` (`setup_repo`).

- [ ] `test_ac_v3_03_test_deleted`, `test_ac_v3_03_criterion_dropped` (iki `test_paths` dizini, Review Focus 2), `test_ac_v3_03_skip_marker_added` (eklenen satır; zaten var olan işaret satırı bildirilmez).
- [ ] `test_ac_v3_04_test_skip_conf`: yalnızca yorum → `doctor` FAIL ve `guard` 2; geçersiz ERE satır numarasıyla; `NONE: reason` geçerli; `test_paths` ayarsız → 2.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 3: Kapı, birleştirme ve R3 (AC-V3-05, 06, 08)

**Files:** Modify `src/lib/job.sh` (`sw_job_gate`), `src/lib/run.sh` (`sw_merge_job`). Test: `tests/job_test.sh`, `tests/merge_test.sh`.

- [ ] `test_ac_v3_05_gate_guard_fails_without_verify`: `verify` çalışmaz (sayaç dosyası), yeniden deneme yok, ayrıntı ilk ihlal, günlükte hepsi.
- [ ] `test_ac_v3_06_merge_refuses_guard`: `touches` dışı yol; `commands.conf`'ta `test = true` yapan iş `verify` çalışmadan ve `gh pr merge` çağrılmadan reddedilir.
- [ ] `test_ac_v3_06_sync_paths_not_counted` (Review Focus 1).
- [ ] `test_ac_v3_08_r3_from_paths`: spec R1, `risk.conf`'ta `src/pay/* = R3`, iş o yola dokunur → escalate.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 4: Değerlendirme yapıtları, `prepare` ve `score` (AC-V3-09, 10, 11)

**Files:** Create `src/eval/sample/**`, `src/eval/cases/NN-*/{diff.patch,expect,kind}`, `src/lib/eval.sh`, `tests/eval_test.sh`. Modify `install.sh` (`eval` ağacı), `src/bin/softwary`.

- [ ] `test_ac_v3_09_prepare_layout`: her vaka bir repo, `main` ve `review` dalı, `expect`/`kind` yok, adlar `case-NN`, eşleme `.softwary/state/eval/map`'te; boş olmayan dizin 2 (Review Focus 3).
- [ ] `test_ac_v3_10_corpus_shape`: en az 10 vaka, tür sayıları; her yama uygulanır; `guard` türleri `guard` 1, diğerleri 0; temiz vakalarda `sh tests/run.sh` geçer.
- [ ] `test_ac_v3_11_score_incomplete`: eksik ve geçersiz kayıtlar listelenir, `eval.conf` yazılmaz, 1.
- [ ] `test_ac_v3_11_score_writes_conf`: sentetik kayıtlarla (bozuklara `changes`, temizlere `approve`, bir temize `changes`) sayılar ve özet; `guard` vakaları kayıt `approve` olsa da yakalanmış sayılır (Review Focus 4).
- [ ] `test_ac_v3_10_install_and_upgrade_ship_eval`.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 5: Eşik ve `status` (AC-V3-12)

**Files:** Modify `src/lib/eval.sh` (`sw_eval_state`), `src/lib/run.sh`, `src/lib/loopconf.sh`, `src/templates/loop.conf`, `src/lib/trace.sh` (`status`), `tests/lib.sh` (`add_eval`). Test: `tests/merge_test.sh`, `tests/eval_test.sh`, `tests/models_test.sh`.

- [ ] `test_ac_v3_12_merge_requires_eval`: `missing`, `stale` (`reviewer.md` ya da `models.conf` değişince), `below` → escalate, `gh pr merge` yok; `ok` → birleşir.
- [ ] `test_ac_v3_12_min_catch_percent_validation`: `-1`, `101`, `x` → `doctor` satırı, `run start` 2; `0` geçerli ama yine `eval.conf` ister (Review Focus 5).
- [ ] `test_ac_v3_12_status_evaluation`.
- [ ] V2 testlerini `add_eval` ile güncelle ve listele.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 6: Skill ve ajan metinleri (AC-V3-13)

**Files:** Create `src/skills/evaluate/SKILL.md`. Modify `src/skills/{implement,run,setup,review}/SKILL.md`, `src/agents/{implementer,reviewer}.md`, `src/templates/artifacts/review.md`, `src/rules/core.md`. Test: `tests/skill_test.sh`.

- [ ] `test_ac_v3_13_excuse_tables`, `test_ac_v3_13_evidence_only_findings`, `test_ac_v3_13_evaluate_skill`, `test_ac_v3_13_setup_asks`; 80 satır ve `help` testleri yeşil.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 7: Bütünleşme (AC-V3-14)

- [ ] `loop_e2e_test.sh` geçerli değerlendirmeyle birleştirmeye gider; ek olarak değerlendirmesiz koşuda ilk işin `auto-merge is off` ile insana bırakıldığı bir test.
- [ ] `sh tests/run.sh` tam; `shellcheck -s sh -x install.sh src/bin/softwary src/lib/*.sh src/targets/*.sh src/hooks/* src/templates/softwary tests/*.sh src/eval/sample/tests/*.sh src/eval/sample/src/*.sh` temiz.
- [ ] Mutasyon: korunan listeden bir kök silme, `touches` eşleşmesinde dizin önekini kaldırma, `criterion dropped` denetimini kapatma, `merge`'de eşik denetimini kapatma, `eval score`'da `guard`'ı saymama; her biri kızarır, geri alınır.
- [ ] `wc -l src/lib/job.sh src/lib/run.sh src/lib/plan.sh src/lib/guard.sh src/lib/eval.sh`.
- [ ] `docs/decisions.md` "V3" (D-83..D-96, yapılana göre), `docs/roadmap.md` V3 notu, `docs/sources.md` durumları (zazencodes korunan yollar, ana daldaki denetim, test gevşetme; addyosmani bahane tabloları; pstack kanıtlı bulgular ve yeniden hesaplama).
- [ ] Güncellenen eski testler ve AC → test tablosu raporlanır.

## AC → test eşlemesi

| AC | Testler |
| --- | --- |
| AC-V3-01, 02, 04 | `guard_test.sh` |
| AC-V3-03 | `guard_test.sh` |
| AC-V3-05 | `job_test.sh` |
| AC-V3-06, 08 | `merge_test.sh` |
| AC-V3-07 | `guard_test.sh` ya da `plan_test.sh` |
| AC-V3-09, 10, 11 | `eval_test.sh` |
| AC-V3-12 | `merge_test.sh`, `eval_test.sh`, `models_test.sh` |
| AC-V3-13 | `skill_test.sh` |
| AC-V3-14 | `sh tests/run.sh` + `shellcheck` + `loop_e2e_test.sh` |
