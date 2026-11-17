# V5 Tanım ve blueprint'i derinleştirme — Uygulama planı

**Goal:** `docs/specs/V5.md`'deki AC-V5-01..14'ü karşılamak: akışlar ve durum makineleri, ürün için TLA+ belirtimleri (`formal check`, `formal install`, `model_check`), değişmez cümlelerinin blueprint onayına girmesi, blueprint eleştirmeni, üretilen durum ve sıra diyagramları, `next`, `handoff` ve v1 aşama skill'lerinin v2'ye katılması.

**Architecture:** Yeni mantık yeni dosyalarda: `src/lib/flows.jq` ve `src/lib/states.jq` (yapı denetimleri, `data.jq` gibi), `src/lib/formal.sh` (`.md` ayrıştırma, TLC çağırma, iz çevirisi, `install`), `src/lib/next.sh` (`next`, `handoff`). `product.sh`'deki `sw_blueprint` ve `sw_digest`, `model.sh`'deki `sw_views`, `verify.sh` ve `doctor.sh` yalnızca çağrı ve küçük eklerle değişir. Yapıt şablonları `src/templates/artifacts/` altına (`flow.json`, `states.json`, `formal.md`, `critique.md`).

**Tech Stack:** POSIX `sh`, `git`, `jq`, `shellcheck`; Java ve `tla2tools.jar` 1.8.0 (projede belirtim varsa).

**Spec:** `docs/specs/V5.md` (approved). Bağlam: `docs/design.md` §5, §6.1, §6.2, §7, §11; `docs/sources.md` §2 ve §5 (pstack'in biçimsel doğrulama yaklaşımı); `docs/decisions.md` D-66..D-71 (ürün, blueprint, onay, analist kaydı), D-85 (korunan yollar), D-108/D-113 (paketin kendi TLA+ belirtimi), D-80 (skill'ler).

## Global Constraints

- Scriptler POSIX `sh`; pakete yeni zorunlu bağımlılık yok (Java ve jar yalnızca belirtimi olan projede ve yalnızca `formal`/`model_check` için).
- `shellcheck -s sh -x` temiz; çıkış kodları `0/1/2`; paket içeriği İngilizce, `docs/` Türkçe.
- Her test `test_` ile başlar, üstündeki yorum kriter kimliğini taşır; önce test, kırmızı, sonra kod.
- Paket içeriği stack'e özgü sözcük denetiminden geçer (AC-M0-09).
- Kararlar `docs/decisions.md`'ye "V5" başlığı altında D-114'ten başlayarak; sapmalar kendi satırına.
- Dal `claude/zen-ramanujan-jy9sc6`; push ve PR'ı orkestratör yapar.

## Kararlar (decisions.md'ye girer)

- **D-114 Spec onayı:** V5 spec'i kullanıcı isteğiyle yazıldığı oturumda `approved` yapıldı (D-42, D-65, D-83, D-97).
- **D-115 Akış dosyası:** `architecture/flows/<id>.json`: `{"id","name","features":["F1"],"participants":["<düğüm unique-id>"],"entities"?:["<varlık id>"],"steps":[{"from","to","action","data"?}],"traits"?:["concurrency"|"retry"|"crash"],"formal"?:"<ad>"}`. `id` `^[a-z][a-z0-9-]*$` ve dosya adı. Katılımcılar CALM düğümleri, varlıklar veri modelinden, özellikler `PRODUCT.md`'den. `traits` boş değilse `formal` zorunlu. Akış gereği: bir özellik iki ya da daha çok düğümün `metadata.features`'ında geçiyorsa `features`'ında onu taşıyan en az bir akış olmalı. Satır biçimi: `architecture/flows/<dosya>: <sorun>`.
- **D-116 Durum makinesi dosyası:** `architecture/states/<varlık id>.json`: `{"entity","initial","states":[...],"final"?:[...],"transitions":[{"from","event","to","guard"?}],"formal":"<ad>"}`. `entity` dosya adıyla aynı ve veri modelinde var; olay adları `^[a-z][a-z0-9_]*$`. Ulaşılabilirlik `jq` ile sabit nokta hesabıdır. `formal` her durum makinesinde zorunludur (design §6.2).
- **D-117 Belirtim kaydı (`<ad>.md`):** Şablon `src/templates/artifacts/formal.md`. Bölümler (başlıklar sabit, İngilizce): `## Invariants` (`| Name | Statement | Harm |`), `## Actions` (`| Action | Statement |`), `## Coverage` (`| Path | Functions |`; kod yokken `planned`), `## Bounds and assumptions` (madde listesi, boş olamaz), `## Last verified` (40 haneli commit ya da `never`), `## Variants` (`| File | Breaks |`; dosya `<ad>-<varyant>.cfg`). Bir değişmez tablo dışında sayılmaz. Durum makinesindeki her olay `## Actions` tablosunda bir eylem olarak geçer: TLA+ eylem adı olayın adıyla birebir aynıdır (dönüştürme yok).
- **D-118 `formal check`:** `src/lib/formal.sh`. Jar: `SW_TLA2TOOLS` ya da `$HOME/.cache/softwary/tla2tools-1.8.0.jar`; adres ve SHA-256 V4'teki (`tests/tlc.sh`) ile aynı ve pakette sabit. Her çağrı `java -XX:+UseParallelGC -cp <jar> tlc2.TLC -workers auto -config <cfg> -metadir <geçici> <tla>` (çalışma dizini `architecture/formal/`). İyi model: çıktı `No error has been found` ve durum sayısı satırdan okunur. Varyant: `Invariant <ad> is violated` ya da (zamansal için) `Temporal properties were violated` ve `## Variants`'taki değişmez bu adı taşır. İyi model başarısızsa iz TLC çıktısından ayrıştırılır (`State <n>: <<Eylem> line ...>` ve ardından gelen `/\ var = değer` satırları); her adım `## Actions` tablosundaki cümleyle ve yalnızca değişen değişkenlerle yazılır; tabloda olmayan eylem adıyla yazılır. Günlük `.softwary/state/logs/formal-<ad>[-<varyant>].log`. Belirtim yoksa `formal: no specs` ve 0.
- **D-119 `formal install`:** `curl -fsSL` (yoksa `wget -q`) ile indirir, `sha256sum` ya da `shasum -a 256` ile denetler; araç yoksa 2. CI şablonu (`src/templates/github/softwary.yml`) `hashFiles('architecture/formal/*.tla') != ''` koşuluyla `actions/setup-java` (temurin 21) ve `./softwary formal install` adımlarını taşır.
- **D-120 `model_check`:** `commands.conf`'ta isteğe bağlı anahtar; `sw_formal_specs_exist` doğruysa zorunlu: `UNSET` ya da `NONE: ...` → `verify`'da `FAIL model_check (required: architecture/formal has specs)` ve `doctor`'da aynı satır. `verify`'daki yeri `contract_check`'ten önce, test ve derlemeden sonradır; `--fast` onu çalıştırmaz. Şablon: `# model_check = ./softwary formal check`. Muafiyet verilebilir (proje denetimidir).
- **D-121 `blueprint check` sırası:** V2 denetimleri, sonra akışlar (D-115), durum makineleri (D-116), belirtim kayıtları (D-117), sonra hepsi temizse `formal check` (Java ya da jar yoksa `blueprint: formal check could not run: ...` ve 2). `formal check` sorunları `blueprint check` çıktısına aynı satırlarla girer.
- **D-122 Onay özeti:** Blueprint özetine her `architecture/formal/*.md` için `## Invariants` tablosunun satırları (başlık ve boşluk normalleştirilmeden, tablonun ham metni) `<blob> architecture/formal/<ad>.md#invariants` girdisi olarak eklenir (blob, tablo metninin `git hash-object --stdin`'i). `.tla`, `.cfg`, akışlar ve durum makineleri özette yoktur (design §5: bilgilendirici). `SW_PROTECTED`'e `architecture/formal/` eklenir.
- **D-123 Eleştirmen kaydı:** `architecture/critique.md`: üst bilgi `digest` (blueprint özeti, D-68 ile hesaplanan, eleştirmen yazdığı anda), `decision: pass|changes`; gövde bulgular (`- <yol> — <sorun> — evidence: ...`). `approve blueprint`: kayıt yok `blueprint: no critique (architecture/critique.md)`, `decision` `pass` değil, ya da `digest` güncel değil (`critique is stale`) → 1. `critique.md` özette yoktur. Ajan `src/agents/blueprint-critic.md`; `models.conf` şablonu `blueprint-critic = opus`; `doctor` mevcut projede eksik anahtarı zaten bildirir (D-78).
- **D-124 Görünümler:** `views.jq` yanına `states-view.jq` ve `flow-view.jq`. Durum: `stateDiagram-v2`, `[*] --> initial`, her geçiş `from --> to : event`, her son durum `--> [*]`. Akış: `sequenceDiagram`, katılımcılar sırasıyla, her adım `from->>to: action`. Üretilen dosyaların ilk satırı yorumdur (`%% generated by ./softwary views from <kaynak>`); sahipsiz tespiti bu satırla yapılır, elle yazılmış `.mmd` silinmez.
- **D-125 `next`:** Sıra: `PRODUCT.md` yok ya da `product check` sorunlu → `define`; ürün onayı güncel değil → `approve product (human)`; model yok ya da `blueprint check` sorunlu (Java yoksa `formal check` atlanır ve neden yazılır) → `blueprint`; eleştirmen kaydı yok, `changes` ya da bayat → `critique`; blueprint onayı güncel değil → `approve blueprint (human)`; `approved` spec yok, `plan check` sorunlu ya da yalnızca `draft` spec var → `plan` ya da `plan approve <spec>` (analist kaydı `pass` ve güncelse); koşu açık ve insanı bekleyen iş varsa `waiting: <işler>`; `planned` dilim varsa `run`; aksi hâlde `none`. Biçim: `next: <adım> (<neden>)`.
- **D-126 `handoff`:** `.softwary/state/handoff.md` başlıkları: `# Handoff`, `## Where` (zaman, dal, `HEAD`), `## Working tree`, `## Next`, `## Approvals`, `## Jobs`, `## Recent events`, `## Notes`. `## Notes` ve altı eski dosyadan aynen taşınır. Skill `src/skills/handoff/SKILL.md`.
- **D-127 Skill birleştirme:** `discover`, `architect`, `specify`, `slice` kaldırılır; bunların yalnızca bu skill'lerde olan gerekli adımları (ör. `specify`'ın kriter yazım kuralı, `slice`'ın `touches` ve `depends_on` kuralları) `define`, `blueprint`, `plan`'a taşınır. Bu skill adlarını anan kurallar (`src/rules/`), `setup`, `AGENTS.md` bloğu ve testler güncellenir. `implement` ve `review` kalır.
- **D-128 Örnek ve test düzeneği:** `tests/fixtures/formal/` altında küçük bir ürün (bir varlık `order`, durumlar `created paid shipped cancelled`), `architecture/states/order.json`, `architecture/formal/order.tla/.cfg/.md` (değişmezler: `ShippedWasPaid`, `CancelledNeverShipped`), iki varyant ve değişmezi bozan bir model kopyası. `tests/lib.sh`'ye `add_formal` (fikstürü kopyalar), `need_tlc` (Java ve jar yoksa `SW_SKIP_FORMAL`'a göre atla ya da başarısız ol), `add_critique` (güncel özetli `pass` kaydı). `tests/tlc.sh` paketteki `formal` koduna dayanacak biçimde sadeleşir; `tests/formal_test.sh` (paketin kendi protokolü) geçmeye devam eder. Güncellenen eski testler PR'da ve bu satırda.

## Review Focus

1. `formal check` iz ayrıştırması TLC 1.8.0'ın gerçek çıktısıyla test edilir (fikstürdeki bozuk modelin çıktısıyla); yalnızca uydurma çıktıyla değil (T3).
2. Değişmezler tablosu özeti, eylem ya da kapsam tablosu değişince değişmez; değişmez cümlesindeki tek harf değişikliği onayı bayatlatır (T4).
3. `architecture/formal/` korunan yol olunca `eval` vakaları ve V3 `guard` testleri bozulmaz; listede sonu `/` olan giriş (T4).
4. `views` sahipsiz silmede yalnızca kendi ürettiği dosyalara dokunur (T5).
5. Kaldırılan skill'ler `upgrade` sonrası `.claude/skills`, `.cursor/skills`, `.agents/skills`'ten silinir; yerel (`local/`) aynı adlı skill varsa korunur (T7).
6. `next` hiçbir dosya yazmaz ve TLC çalıştırmaz (yavaş olmasın): belirtimler için yalnızca yapı denetimlerine bakar (T6).

---

### Task 1: Akışlar ve durum makineleri (AC-V5-01, 02)

**Files:** Create `src/lib/flows.jq`, `src/lib/states.jq`, `src/templates/artifacts/flow.json`, `src/templates/artifacts/states.json`, `tests/flows_test.sh`, `tests/states_test.sh`. Modify `src/lib/product.sh` (`sw_blueprint`).

- [ ] Her denetim satırı için ayrı test (`test_ac_v5_01_*`, `test_ac_v5_02_*`), geçerli dosyalar için temiz çıktı.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 2: Belirtim kaydı ve `blueprint check` bağlantısı (AC-V5-03)

**Files:** Create `src/lib/formal.sh` (ayrıştırma kısmı), `src/templates/artifacts/formal.md`, `tests/fixtures/formal/`. Modify `src/lib/product.sh`.

- [ ] `test_ac_v5_03_*`: eksik dosya, eksik bölüm, varyantı olmayan değişmez, bilinmeyen değişmeze başvuran varyant, olmayan varyant dosyası, eylem tablosunda olmayan olay.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 3: `formal check`, `formal install`, `model_check` (AC-V5-04, 05, 06, 13)

**Files:** Modify `src/lib/formal.sh`, `src/bin/softwary` (`formal`, `help`), `src/lib/verify.sh`, `src/lib/doctor.sh`, `src/lib/config.sh`, `src/templates/commands.conf`, `src/templates/github/softwary.yml`, `tests/tlc.sh`. Create `tests/formal_check_test.sh`.

- [ ] `test_ac_v5_04_good_and_variants`, `test_ac_v5_04_violation_path` (bozuk modelde `FAIL: ShippedWasPaid violated`, numaralı cümleler), `test_ac_v5_04_variant_did_not_fail`, `test_ac_v5_04_no_java` (sahte `PATH`).
- [ ] `test_ac_v5_05_install` (yerel bir dosya adresiyle: `SW_TLA2TOOLS_URL` yalnızca testte; özet uyuşmazlığı → 2 ve dosya silinmiş), CI şablonunda adımlar.
- [ ] `test_ac_v5_06_model_check_required`, `..._skip_without_specs`, `..._doctor_java`.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 4: Onay ve korunan yol (AC-V5-07, 08)

**Files:** Modify `src/lib/product.sh` (`sw_digest`, `sw_approve`), `src/lib/guard.sh` (`SW_PROTECTED`), `src/templates/models.conf`. Create `src/agents/blueprint-critic.md`, `src/templates/artifacts/critique.md`.

- [ ] `test_ac_v5_07_invariant_change_stales`, `test_ac_v5_07_actions_change_keeps`, `test_ac_v5_07_formal_protected`.
- [ ] `test_ac_v5_08_critique_required` (yok, `changes`, bayat, güncel `pass`).
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 5: Görünümler (AC-V5-09)

**Files:** Create `src/lib/states-view.jq`, `src/lib/flow-view.jq`. Modify `src/lib/model.sh` (`sw_views`).

- [ ] `test_ac_v5_09_state_and_flow_views`, `test_ac_v5_09_orphan_removed_handwritten_kept`, `test_ac_v5_09_check`.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 6: `next` ve `handoff` (AC-V5-10, 11)

**Files:** Create `src/lib/next.sh`, `src/skills/handoff/SKILL.md`, `tests/next_test.sh`. Modify `src/bin/softwary`.

- [ ] `test_ac_v5_10_each_step`: boş repodan `none`'a kadar her adım için bir senaryo; `next` dosya yazmaz.
- [ ] `test_ac_v5_11_handoff_sections_and_notes_kept`.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 7: Skill birleştirme ve metinler (AC-V5-12)

**Files:** Delete `src/skills/discover`, `architect`, `specify`, `slice`. Modify `src/skills/define`, `blueprint`, `plan`, `setup`, `src/rules/*`, `install.sh` gerekirse, `tests/skill_test.sh`, `tests/upgrade_test.sh`, `tests/sync_test.sh`.

- [ ] `test_ac_v5_12_*`: kaldırılan skill'ler pakette ve `upgrade` sonrası üç araçta yok; `define` ve `blueprint` zorunlu ifadeleri taşır (tek soru ve önerili cevap, akış, durum makinesi, `formal check`, `blueprint-critic`); 80 satır; yalnızca `help` komutları.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 8: Bütünleşme (AC-V5-13, 14)

**Files:** `tests/blueprint_formal_e2e_test.sh`, `docs/decisions.md`, `docs/roadmap.md`, `docs/sources.md`, `docs/design.md` (yalnızca §10'daki yapıt ağacı gerekiyorsa).

- [ ] `test_ac_v5_13_end_to_end`: fikstürle `blueprint check` (formal dahil) → `next` `critique` → eleştirmen kaydı → `approve blueprint` → `verify` (`model_check = ./softwary formal check`) PASS; değişmez cümlesi değişince onay bayat.
- [ ] Bütün suite, `shellcheck`, mutasyon denetimi (her yeni kural bir kez bozulur, ilgili test kırmızı; D-128'e bir satır).
- [ ] `decisions.md` "## V5" (D-114..D-128 ve sapmalar), `roadmap.md` V5 notu, `sources.md` durum sütunları (sorgulama, alan modelleme, oturum devri, biçimsel doğrulama).
- [ ] Commit.

## AC → test eşlemesi

| AC | Test |
| --- | --- |
| AC-V5-01 | `flows_test.sh` |
| AC-V5-02 | `states_test.sh` |
| AC-V5-03 | `formal_check_test.sh` (kayıt denetimleri) |
| AC-V5-04..06 | `formal_check_test.sh` |
| AC-V5-07, 08 | `approve_test.sh`, `guard_test.sh` |
| AC-V5-09 | `views_test.sh` |
| AC-V5-10, 11 | `next_test.sh` |
| AC-V5-12 | `skill_test.sh`, `upgrade_test.sh` |
| AC-V5-13 | `blueprint_formal_e2e_test.sh`, `formal_check_test.sh` |
| AC-V5-14 | bütün suite |
