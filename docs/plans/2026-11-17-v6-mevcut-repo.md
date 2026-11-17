# V6 Mevcut repo — Uygulama planı

**Goal:** `docs/specs/V6.md`'deki AC-V6-01..15'i karşılamak:
- muaf denetimler için değişen dosyalarda kapsamlı denetim (`<anahtar>_files`);
- muafiyetin kapsamlı komut şartı;
- biçimsel belirtimde süreli bulgu (`## Findings`);
- muafiyet ve bulguların `status` ve `handoff`'ta görünmesi;
- mevcut repo için `setup`, `define` ve `blueprint` yolları;
- `install.sh` koruması;
- örnek mevcut repo ile uçtan uca test.

**Architecture:**
- Kapsamlı denetim mantığı yeni `src/lib/scoped.sh`'te: değişen dosya listesi, `{files}` yerleştirme, `<anahtar>_files` doğrulama.
- `verify.sh` `sw_verify_run`'da muaf ve kırmızı denetimden sonra onu çağırır.
- `doctor.sh` ve `run.sh` şart denetimini çağırır.
- Bulgu mantığı `formal.sh`'te: kayıt ayrıştırma, geçici `.cfg` ve `formal check` akışı.
- Özet eki `product.sh`'te (`sw_digest`, `#findings` girdisi).
- `status` ve `handoff` ortak bir `sw_status_waivers` fonksiyonunu kullanır (`waivers.sh`'te).
- İş kapısı ve birleştirme zaten `verify --base` çağırdığı için `job.sh` ve `merge.sh` değişmez; testle gösterilir.

**Tech Stack:** POSIX `sh`, `git`, `jq`, `shellcheck`; Java ve `tla2tools.jar` 1.8.0 (yalnızca `formal` testleri).

**Spec:** `docs/specs/V6.md` (approved). Bağlam:
- `docs/design.md` §3 İlke 4, §5, §7, §9, §11;
- `docs/decisions.md`: D-35 (değişiklik kümesi), D-38, D-51, D-55 (muafiyet), D-59, D-84/D-85 (`guard`, korunan yollar), D-117..D-123 (belirtim kaydı, `formal check`, özet, eleştirmen), D-129..D-135.

## Global Constraints

- Scriptler POSIX `sh`; yeni bağımlılık yok.
- `shellcheck -s sh -x` temiz; çıkış kodları `0/1/2`; paket içeriği İngilizce, `docs/` Türkçe.
- Her test `test_` ile başlar, üstündeki yorum kriter kimliğini taşır; önce test, kırmızı, sonra kod.
- Paket içeriği stack'e özgü sözcük denetiminden geçer (AC-M0-09). Fikstür kodu da stack'e özgü olmamalı: düz `sh` scriptleri.
- Kararlar `docs/decisions.md`'ye "## V6" başlığı altında D-137'den başlayarak; sapmalar kendi satırına.
- Dal `claude/zen-ramanujan-jy9sc6`; push ve PR'ı orkestratör yapar.

## Kararlar (decisions.md'ye girer)

- **D-137 Spec onayı:** V6 spec'i kullanıcı isteğiyle yazıldığı oturumda `approved` yapıldı (D-42, D-65, D-83, D-97, D-114).
- **D-138 Kapsamlı denetim:** *insan onaylı (2026-11-17): muaf denetim değişen dosyalarda zorunlu.*
  - **Anahtarlar:** `<anahtar>_files`, muaf tutulabilir her proje denetimi için (D-55 listesi: `format_check lint typecheck test build security contract_check arch_check model_check`).
  - **Değer:** `{files}` geçen bir komut ya da `NONE: <gerekçe>`. `{files}` geçmeyen komut `doctor`'da `FAIL`, `verify`'da 2 verir.
  - **Değişen dosyalar:** `sw_changed_since <base>` kümesi (D-35: `--no-renames`, izlenmeyenler dahil). Bu kümeden `src_paths` ya da `test_paths` altında olan ve çalışma ağacında dosya olarak var olanlar alınır. Sıra sabittir (`sort`).
  - **Yerleştirme:** her yol tek tırnakla tırnaklanır (içindeki `'` `'\''` olur) ve boşlukla birleştirilir. `{files}` bu metinle değiştirilir ve sonuç `sh -c` ile çalışır.
  - **Çıktı ve günlük:** satır adı `<anahtar> (changed files)`; günlük `.softwary/state/logs/verify-<anahtar>-files.log`. Satır `PASS`/`FAIL` sayaçlarına girer.
- **D-139 Hangi `verify` kapsamlı komutu çalıştırır:**
  - `--base <ref>`: o tabana karşı.
  - `--fast`: `integration_branch` çözülürse ona karşı, yalnızca `format_check lint typecheck` için.
  - Bayraksız: çalıştırmaz, `SKIP (no base)` yazar.
  - Kapsamlı komut yalnızca şu durumda çalışır: denetim başarısız, muafiyeti geçerli ve süresi dolmamış. Muafiyetsiz, geçen ya da süresi dolmuş denetimde kapsamlı satır hiç yazılmaz.
- **D-140 Muafiyet şartı:** `doctor`, her geçerli muafiyet anahtarı için `<anahtar>_files`'ı denetler; yoksa ya da `UNSET` ise `FAIL <anahtar>_files (required: <anahtar> has a waiver)`. `run start` aynı denetimi `bootstrap`'tan sonra yapar ve 2 döner. `.softwary/` korunan yol olduğu için döngü muafiyet ekleyemez; bu V3 `guard` testleriyle zaten sınanır, burada bir regresyon testi yeterli.
- **D-141 Bulgu kaydı:** *insan onaylı (2026-11-17): süreli bulgu kaydı.*
  - **Tablo:** `## Findings` isteğe bağlıdır; biçimi `| Invariant | Until | Reason |`. Tarih `sw_valid_date` ile denetlenir.
  - **`blueprint check` sorunları:** değişmez `## Invariants` tablosunda yok, geçersiz tarih, boş gerekçe ve aynı değişmez iki kez.
  - **Şablon:** `formal.md`'ye boş tablo yorumla eklenir.
- **D-142 Bulgulu `formal check`:**
  - **Geçici `.cfg`'ler:** iyi `.cfg`'nin `INVARIANT`/`INVARIANTS` satırlarından bulgu değişmezleri çıkarılır. Bulgu değişmezi başına yalnızca o değişmezi taşıyan bir `.cfg` daha üretilir. Bütün geçici dosyalar D-130'daki geçici kopyada kalır.
  - **İyi model:** bulgusuz kalan değişmezlerle geçmeli. Geçmezse V5'teki gibi `FAIL`.
  - **Bulgu:** başarısız olmalı → `FINDING` ve yol (`-workers 1`, D-131). Geçerse `no longer reproduces (remove it)` ve sonuç `PASS`.
  - **Süre:** dolmuşsa `FAIL ... (finding expired <tarih>)` ve 1.
  - **Varyantlar:** değişmez.
  - **`PASS` satırındaki durum sayısı:** bulgusuz çalışmanınkidir.
- **D-143 Özet:** `sw_digest`'e her `architecture/formal/*.md` için, `## Findings` tablosu varsa `<blob> architecture/formal/<ad>.md#findings` girdisi eklenir; blob, tablonun ham satırlarıdır (`#invariants` gibi). Tablo yoksa girdi yoktur. Böylece V5 projelerinde özet değişmez: bulgusuz kayıtta onay bayatlamaz.
- **D-144 Görünürlük:** `sw_status_waivers` iki tür satır yazar:
  - `waiver <anahtar>: until <tarih> (<n> days left|expired): <gerekçe>`;
  - `finding <ad>/<değişmez>: until ...`.
  Kalan gün POSIX `sh`'te hesaplanır: tarihten gün sayısı, `date` farkına güvenmeden, `sw_valid_date`'in yanına bir yardımcıyla. `status`'ta ve `handoff`'ta `## Waivers and findings` bölümü olarak yer alır; boşsa `(none)`.
- **D-145 Skill'ler:**
  - **`setup`:** mevcut repo adımı (D-38/D-59'daki model ve taban çizgisi ADR'si) kalkar. Yerine şu adım gelir: `verify` çalıştırılır; her `FAIL` proje denetimi için insana düzeltme ya da muafiyet sorulur. Muafiyette tarih, gerekçe ve `<anahtar>_files` (ya da insanın verdiği gerekçeyle `NONE`) sorulur. Sonraki adımlar `define` ve `blueprint`.
  - **`define`:** koddan başlama adımı.
  - **`blueprint`:** koddan çıkarma, `active` bileşenler, gerçek kapsam, `0001-model-from-code` ADR'si (her bileşenin yolları; `proposed`) ve bulgu kuralı.
  - **Sınırlar:** 80 satır sınırı ve `help` komutları kuralı sürer.
- **D-146 `install.sh`:** hedefte `softwary` varsa ve ya dizin ya da ilk iki satırında paketin sarmalayıcısının imza satırı yoksa: `install: <hedef>/softwary exists and is not softwary's wrapper` ve 2. Bu denetim plan listelenmeden önce yapılır ve hiçbir şey yazılmaz. İmza satırı `src/templates/softwary`'deki yorum satırıdır; gerekirse eklenir. Eski sürümün sarmalayıcısı da tanınmalıdır (`upgrade`/yeniden kurulum bozulmamalı).
- **D-147 Fikstür:** `tests/fixtures/existing/`:
  - `app/` altında birkaç `sh` dosyası: `order.sh`, sipariş durumlarını değiştirir; eski koddaki bir yol ödenmemiş siparişi gönderebilir.
  - `checks/lint.sh`: verilen dosyalarda ya da dizinde `XXX` geçen satırları bildirir, varsa 1.
  - `checks/test.sh`: verilen ya da bütün `tests/*.sh`'leri çalıştırır.
  - `tests/`: biri başarısız olan eski testler.
  - `README.md`.
  - Ayrıca hazır `product/PRODUCT.md`, `architecture/` (model, veri modeli, `states/order.json`, `formal/order.*` ve `## Findings`'te `ShippedWasPaid`) ve bir spec ve dilim.
  - `tests/lib.sh`'ye `add_existing` gelir: fikstürü test reposuna kopyalar ve ilk commit'i yapar.
  - Uçtan uca test V4/V5 yardımcılarını (sahte `gh`, çıplak `origin`, `approve_blueprint`, `need_tlc`) kullanır.

## Review Focus

1. `{files}` yerleştirmesi boşluk, tırnak ve `-` ile başlayan dosya adlarıyla güvenli olmalı; komut enjeksiyonu yok (T1 testleri bu adlarla).
2. Kapsamlı komut iş kapısında işin worktree'sinde, tabana karşı çalışmalı; ana checkout'un değişiklikleri karışmamalı (T2).
3. Bulgu için geçici `.cfg` üretimi `INVARIANTS` çok satırlı biçimini de doğru ayıklamalı. İyi modelin bulgusuz çalışması, bulgu olmayan bir değişmezin ihlalini gizlememeli (T3: bulgu varken başka bir değişmezi bozan model `FAIL`).
4. V5 projelerinde (bulgusuz kayıt) blueprint özeti değişmemeli (T3).
5. `install.sh` reddi hiçbir dosya yazmadan olmalı; aynı paketin yeniden kurulumu ve `upgrade` bozulmamalı (T5).
6. Skill metinleri: `setup` mevcut repoda model çizmez; `blueprint` bulguda değişmezi zayıflatmaz (T4).

---

### Task 1: Kapsamlı denetim ve `verify` (AC-V6-01, 02, 03)

**Files:**
- Create: `src/lib/scoped.sh`, `tests/scoped_test.sh`.
- Modify: `src/bin/softwary` (source), `src/lib/verify.sh`, `src/lib/config.sh` (anahtar doğrulama gerekiyorsa), `src/templates/commands.conf`.

- [ ] `test_ac_v6_01_files_placeholder_required`, `test_ac_v6_01_none_allowed`.
- [ ] `test_ac_v6_02_*`:
  - muaf + değişen dosyada temiz → `PASS`;
  - değişen dosyada hata → `FAIL` ve 1;
  - değişen dosya yok → `SKIP (no changed files)`;
  - `NONE` → `SKIP (<gerekçe>)`;
  - süresi dolmuş muafiyet ya da geçen denetim kapsamlı satır yazmaz;
  - boşluklu, tırnaklı ve `-` ile başlayan dosya adı;
  - silinen dosya listeye girmez.
- [ ] `test_ac_v6_03_fast_uses_integration_branch`, `test_ac_v6_03_plain_verify_skips`.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 2: Muafiyet şartı, kapı ve birleştirme (AC-V6-04, 05)

**Files:**
- Modify: `src/lib/doctor.sh`, `src/lib/run.sh`.
- Create: `tests/scoped_loop_test.sh`.

- [ ] `test_ac_v6_04_doctor_requires_files_key`, `test_ac_v6_04_run_start_refuses`.
- [ ] `test_ac_v6_05_gate_fails_on_changed_file`, `test_ac_v6_05_gate_passes_clean_change`, `test_ac_v6_05_merge_recomputes` (birleştirme anında kapsamlı denetim yeniden çalışır).
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 3: Biçimsel bulgu (AC-V6-06, 07, 08)

**Files:**
- Modify: `src/lib/formal.sh`, `src/lib/product.sh` (`sw_digest`), `src/templates/artifacts/formal.md`.
- Create: `tests/fixtures/formal-finding/` (ya da `tests/fixtures/existing/` içinden kullan), `tests/formal_finding_test.sh`.

- [ ] `test_ac_v6_06_*`: tabloda olmayan değişmez, geçersiz tarih, boş gerekçe, yinelenen satır.
- [ ] `test_ac_v6_07_*`:
  - bulgu `FINDING` ve yol, 0;
  - süresi dolmuş bulgu → `FAIL` ve 1;
  - artık bozulmayan bulgu → `no longer reproduces`;
  - bulgu varken başka bir değişmezi bozan model → `FAIL`;
  - `INVARIANTS` çok satırlı `.cfg`;
  - geride `*_TTrace_*` kalmaz.
- [ ] `test_ac_v6_08_findings_change_stales`, `test_ac_v6_08_no_findings_digest_unchanged` (V5 fikstürünün özeti V5'teki değeriyle aynı).
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 4: Görünürlük ve skill'ler (AC-V6-09, 10, 11, 12)

**Files:**
- Modify: `src/lib/waivers.sh`, `src/lib/trace.sh` (`sw_status`), `src/lib/next.sh` (`handoff`), `src/skills/setup/SKILL.md`, `src/skills/define/SKILL.md`, `src/skills/blueprint/SKILL.md`, `tests/skill_test.sh`.
- Create: `tests/status_waivers_test.sh`.

- [ ] `test_ac_v6_09_status_lists_waivers_and_findings` (kalan gün ve `expired`), `test_ac_v6_09_handoff_section`.
- [ ] `test_ac_v6_10_setup_existing_repo_text`: `setup` mevcut repoda model çizmez, muafiyet ve `_files` sorar. `test_ac_v1_08_*` buna göre güncellenir; gerekçesi PR'da.
- [ ] `test_ac_v6_11_define_from_code`, `test_ac_v6_12_blueprint_from_code` (bulgu, değişmezi zayıflatmama, `active`, ADR yolları); 80 satır; `help` komutları.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 5: `install.sh` koruması (AC-V6-13)

**Files:**
- Modify: `install.sh`, `src/templates/softwary` (imza gerekiyorsa), `tests/install_test.sh`.

- [ ] `test_ac_v6_13_refuses_foreign_softwary_file`, `..._dir`: hiçbir dosya yazılmaz, 2.
- [ ] `test_ac_v6_13_reinstall_and_upgrade_ok`.
- [ ] `test_ac_v6_13_agents_and_claude_kept` (işaretçi dışı içerik `sync` sonrası aynen).
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 6: Fikstür ve uçtan uca test (AC-V6-14, 15)

**Files:**
- Create: `tests/fixtures/existing/`, `tests/existing_e2e_test.sh`.
- Modify: `tests/lib.sh` (`add_existing`), `docs/decisions.md`, `docs/roadmap.md`, `docs/sources.md` (gerekiyorsa), `docs/design.md` (§11'e `<anahtar>_files` satırı; §5 formal satırına bulgu).

- [ ] `test_ac_v6_14_existing_repo_end_to_end`:
  1. Kur ve yapılandır; `verify` kırmızı (lint, test).
  2. Muafiyetler ve `_files` yaz; `verify --base` sarı ve geçer.
  3. Ürün ve blueprint denetimleri (`FINDING` dahil), eleştirmen, onaylar, plan.
  4. Bir iş değişen dosyaya `XXX` ekler → `gate_fail`; düzeltilmiş tur → `gate_pass` → PR → birleşme.
  5. Muafiyet ve bulgu tarihleri 2000'e çekilince `verify` ve `formal check` kırmızı.
- [ ] Bütün suite, `shellcheck`, mutasyon denetimi (her yeni kural bir kez bozulur, ilgili test kırmızı; kararlara bir satır).
- [ ] `decisions.md` "## V6" (D-137..D-147 ve sapmalar, değişen eski testler), `roadmap.md` V6 notu.
- [ ] Commit.

## AC → test eşlemesi

| AC | Test |
| --- | --- |
| AC-V6-01..03 | `scoped_test.sh` |
| AC-V6-04, 05 | `scoped_loop_test.sh` |
| AC-V6-06..08 | `formal_finding_test.sh` |
| AC-V6-09 | `status_waivers_test.sh` |
| AC-V6-10..12 | `skill_test.sh` |
| AC-V6-13 | `install_test.sh` |
| AC-V6-14 | `existing_e2e_test.sh` |
| AC-V6-15 | bütün suite |
