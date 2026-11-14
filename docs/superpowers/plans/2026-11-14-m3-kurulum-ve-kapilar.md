# M3 Kurulum ve kapılar — Uygulama planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docs/specs/M3.md`'deki AC-M3-01..09'u karşılamak: `setup` skill'i, git hook'ları, CI ve CODEOWNERS şablonları, ADR denetimi (`trace` + `adr`), `verify --base` ve `upgrade`.

**Architecture:** Her şey mevcut düzenin üstüne biner: POSIX `sh` kütüphaneleri `src/lib/`'de, `bin/softwary` dağıtıcısı, `install.sh` yönetilen ağaçları kopyalar. ADR mantığı tek yeni dosyada (`src/lib/adr.sh`) toplanır; hook'lar `src/hooks/`, şablonlar `src/templates/github/`, skill `src/skills/setup/` altına girer. `upgrade`, yeni paketin `install.sh --upgrade`'ini çağırıp `sync` çalıştırır; yönetilen dosya kümesinin tek tanımı `install.sh`'taki plandır.

**Tech Stack:** POSIX `sh`, `git`, `jq`, `shellcheck`. Test düzeneği `tests/lib.sh` (`sh tests/run.sh`).

**Spec:** `docs/specs/M3.md` (approved). Bağlam: `docs/design.md`, `docs/decisions.md` (D-01..D-33).

## Global Constraints

- Scriptler POSIX `sh`; ek bağımlılık yok (yalnızca `git`, `jq`); `shellcheck -s sh` temiz (D-13, D-14).
- Çıkış kodları: `0` geçti, `1` başarısız, `2` yapılandırma/kullanım (design §4).
- Paket içeriği (skill, şablonlar, hook'lar, mesajlar) İngilizce; `docs/` Türkçe.
- Her test fonksiyonu `test_` ile başlar, üstündeki yorum kabul kriteri kimliğini taşır (D-13).
- `install.sh` `.github/`'a yazmaz; yalnızca `.softwary/templates/` altına koyar (AC-M3-05).
- Karar gerektiren her seçim `docs/decisions.md`'ye D-34'ten başlayarak yazılır (design §10).
- Her commit mesajı sistemin verdiği iki satırla biter (`Co-Authored-By: …` ve `Claude-Session: …`). Dal: `claude/dreamy-dirac-rmwxt8`; PR açılmaz.
- Test yardımcılarıyla commit atarken `--no-verify` kullanılır: `core.hooksPath` artık her test deposunda ayarlı olduğundan hook, testin kendi kurulumunu engellemesin. Yalnızca `hooks_test.sh` gerçek hook'u dener.

## Review Focus

Spec'in ima ettiği ama kabul kriterlerinin doğrudan sınamadığı girdiler, en olasıdan başlayarak; her birinin testi sahibi task'tadır:

1. Bir sözleşme dosyası taşınır ya da silinir; git yeniden adlandırmayı tek yol olarak gösterir ve eski yol kaybolur → yine ADR istenmeli (T2: `--no-renames`).
2. ADR'nin `affects`'i `architecture/../specs`, mutlak yol ya da yalın `architecture/` ile `architecture/`'dan kaçar ya da her şeyi kapsar → geçersiz sayılmalı (T1).
3. Kurulum hedefi başka bir reponun alt dizini ya da `.git`'i dosya olan bir worktree'dir → üst repoya dokunulmaz, kurulum çökmez (T3).
4. `CODEOWNERS`/iş akışında yorum satırındaki `UNSET` ve `specs/**`, `*` gibi desen biçimleri → yorum sayılmaz, bu biçimler kapsar (T4).
5. `upgrade` sürüm karşılaştırması sayısaldır (`0.10.0` > `0.9.0`) ve yol göreli verilebilir; bozuk sürüm dizgesi 2 verir (T6).

---

### Task 1: ADR üst bilgisi denetimi (AC-M3-03)

**Files:**
- Create: `src/lib/adr.sh`, `tests/adr_test.sh`
- Modify: `src/bin/softwary` (adr.sh'ı kaynakla), `src/lib/trace.sh` (`sw_trace` içinde `sw_trace_adrs` çağır; özet satırına `, N ADR(s)` ekle), `src/templates/artifacts/adr.md` (`affects` yorumu: "repo paths inside architecture/, comma-separated"), `tests/lib.sh`, `tests/risk_test.sh` (yerel `commit_all`'ı sil), `docs/decisions.md`

**Interfaces:**
- Produces (`src/lib/adr.sh`): `SW_ADR_REL=architecture/decisions`; `SW_ADR_FIELDS="id title status affects"` (hepsi boş olamaz); `SW_ADR_STATUSES="proposed accepted superseded rejected"`; `sw_trace_adrs` (trace.sh'ın `sw_tr_fields`, `sw_tr_enum`, `sw_tr_problem`'ini kullanır, `_tr_adrs` sayar); `sw_adr_entry_scope ENTRY` → `0` ise `ENTRY` `architecture/` içinde geçerli biçimde (kural: `architecture/` + en az bir karakter, `..` parçası yok, `/` ile başlamaz).
- Produces (`tests/lib.sh`): `commit_all MESSAGE` (`git add -A` + `commit --no-verify`, kimlik `-c user.name=t -c user.email=t@example.com`); `write_adr ID STATUS AFFECTS` → `architecture/decisions/ID-x.md`, `title: Decision ID`.

- [ ] **Step 1: `tests/lib.sh`'ye `commit_all` ve `write_adr`'ı ekle; `risk_test.sh`'deki yerel `commit_all`'ı sil.** `sh tests/risk_test.sh` hâlâ geçmeli.
- [ ] **Step 2: `tests/adr_test.sh`'de başarısız testleri yaz** (`setup_repo`, `write_adr`, `sw trace`):
  - `test_ac_m3_03_valid_adr_passes`: `0001 accepted architecture/model/system.calm.json` → RC 0, çıktı `1 ADR(s)`.
  - `test_ac_m3_03_missing_and_invalid_fields`: `affects` yok, `status: maybe`, `title: UNSET`, `id` boş → RC 1; satırlar `architecture/decisions/0001-x.md: affects: missing`, `status: 'maybe' must be one of proposed, accepted, superseded, rejected`, `title: is UNSET`, `id: is empty`.
  - `test_ac_m3_03_id_must_match_file_name`: `0002-x.md` içinde `id: 0003` → `id: '0003' does not match the file name 0002-x.md`; `adr.md` adlı dosya → `file name must be NNNN-<name>.md`.
  - `test_ac_m3_03_affects_paths`: `specs/001-login/spec.md`, `architecture/../specs`, `/etc/passwd`, `architecture/` (yalın) → her biri ayrı satır `affects: '<girdi>' is outside architecture/`; `architecture/contracts/nope.yaml` → `affects: '<girdi>' not found`; var olan `architecture/model` (dizin) hata vermez. Virgülle ayrılmış birden çok girdi tek tek denetlenir.
- [ ] **Step 3:** `sh tests/adr_test.sh` → FAIL (`sw_trace_adrs` yok).
- [ ] **Step 4: `sw_trace_adrs`'i uygula.** `architecture/decisions/*.md` dosyalarını gez; dosya adı `^[0-9]{4}-[a-z0-9][a-z0-9-]*\.md$` olmalı, `id` ilk dört hane olmalı; alanları `sw_tr_fields`, durumu `sw_tr_enum` ile denetle; `affects` girdilerini `sw_list` ile ayır, her birini `sw_adr_entry_scope` ve `[ -e "$SOFTWARY_ROOT/<girdi>" ]` ile sına. Mesajlar yukarıdaki metinlerle birebir. Dizin yoksa sessizce geç.
- [ ] **Step 5:** `sh tests/adr_test.sh && sh tests/trace_test.sh && sh tests/risk_test.sh && sh tests/install_test.sh` → hepsi PASS.
- [ ] **Step 6: `docs/decisions.md`'ye D-34 yaz** (`affects` repo yoludur, `architecture/` içinde ve var olmalı, dizin girdisi altındakileri kapsar; ADR'de dört alan da boş olamaz; yol kuralı). Commit: `git add -A && git commit -m "M3: trace checks ADR front matter"`.

---

### Task 2: `adr` komutu ve `verify --base` (AC-M3-04)

**Files:**
- Modify: `src/lib/adr.sh`, `src/lib/verify.sh`, `src/bin/softwary` (dispatch + usage), `tests/adr_test.sh`, `docs/design.md` (§4 komut listesine `adr`), `docs/decisions.md`

**Interfaces:**
- Consumes: T1 `write_adr`, `commit_all`.
- Produces: `sw_base_commit REF` → merge-base'i basar; yoksa `adr: base '<ref>' not found (use --base <ref>)` ya da `adr: no common commit between '<ref>' and HEAD` basıp `2` döner. `sw_changed_since COMMIT` → `git diff --no-renames --name-only COMMIT --` + `git ls-files --others --exclude-standard`, sıralı tekil. `sw_adr_covers ENTRY PATH` → `PATH = ENTRY` ya da `PATH`, sondaki `/`'sı atılmış `ENTRY/` ile başlıyorsa 0. `sw_adr [--base REF]` (varsayılan `main`; `0` geçti, `1` kapsanmayan yol, `2` taban/kullanım).
- Kural: kapıya takılan yollar `$SW_MODEL_REL` ve `architecture/contracts/` altındaki her şeydir (silinenler dahil). Kapsayan ADR, **değişiklik kümesinde** (eklenmiş/değişmiş/izlenmeyen, hâlâ var olan) `architecture/decisions/*.md` dosyası olmalı ve `status: accepted` olmalı. Yalnızca `proposed` ADR kapsıyorsa çıktı satırı `<yol>: awaiting human acceptance (ADR <id> is proposed)`; hiçbiri kapsamıyorsa `<yol>: no accepted ADR in this change covers it`. Geçen yollar `<yol>: covered by ADR <id>`. Gerekmiyorsa `adr: no model or contract changes`.
- Produces: `verify [--fast] [--base <ref>]`: `--base` verilirse paket denetimlerinin sonuna `adr` (komut: `sh "$SOFTWARY_HOME/bin/softwary" adr --base <ref>`) eklenir; `--base` yoksa `adr` çalışmaz (varsayılan `main` yalnızca `./softwary adr` içindir; aksi hâlde taban dalı olmayan her depo M0–M2 testlerinde 2 verirdi). `--fast` ile `--base` birlikte kullanım hatasıdır (2). Taban yoksa `verify` hiçbir kontrol çalıştırmadan 2 verir.

- [ ] **Step 1: Başarısız testleri yaz** (`tests/adr_test.sh`; yardımcı `setup_adr`: `setup_repo`, `conf_all true`, `git symbolic-ref HEAD refs/heads/main`, `commit_all base`, `git checkout -qb feature`):
  - `test_ac_m3_04_no_gated_change_passes`: yalnız bir kaynak dosya değişir → RC 0.
  - `test_ac_m3_04_model_change_needs_accepted_adr`: modele `jq` ile alan eklenir → RC 1, `…system.calm.json: no accepted ADR`; `accepted` ADR (`affects` modeli gösterir) eklenince RC 0, `covered by ADR 0001`.
  - `test_ac_m3_04_proposed_adr_awaits_human`: `proposed` ADR → RC 1, `awaiting human acceptance`; `superseded` ve `rejected` ADR de kapsamaz.
  - `test_ac_m3_04_adr_must_be_in_the_change`: `accepted` ADR `main`'de commit'li, model `feature`'da değişir → RC 1.
  - `test_ac_m3_04_contracts`: izlenmeyen `architecture/contracts/api.yaml` → RC 1; `affects: architecture/contracts` (dizin) kapsar → 0; `affects: architecture/model` kapsamaz → 1.
  - `test_ac_m3_04_renamed_or_deleted_contract`: `main`'de commit'li sözleşme `git mv` ile `docs/api.yaml`'a taşınır → RC 1 ve çıktıda **eski** yol; ayrı testte silinir → RC 1.
  - `test_ac_m3_04_base_not_found_exits_2`: `sw adr --base nope` → 2; `main` olmayan depoda `sw adr` → 2.
  - `test_ac_m3_04_verify_base`: sözleşme değişikliği + ADR'siz `sw verify --base main` → RC 1, `adr +FAIL`, `adr` satırı `trace` satırından sonra; ADR eklenince `adr +PASS` ve RC 0; `sw verify` (bayraksız) çıktısında `adr` yok; `sw verify --fast --base main` → 2; `sw verify --base nope` → 2 ve çıktıda `PASS` yok. (Değişiklik olarak model değil sözleşme kullan: model değişirse `views --check` de başarısız olur.)
- [ ] **Step 2:** `sh tests/adr_test.sh` → yeni testler FAIL.
- [ ] **Step 3: `sw_base_commit`, `sw_changed_since`, `sw_adr_covers`, `sw_adr`'ı `adr.sh`'a yaz;** `bin/softwary`'e `adr` dalı ve usage satırı (`adr [--base <ref>]`, `verify [--fast] [--base <ref>]`) ekle. ADR üst bilgisini okurken `sw_fm_read`/`sw_fm_get` kullan; üst bilgisi geçersiz ADR kapsamaz sayılır (hatayı `trace` bildirir).
- [ ] **Step 4: `sw_verify`'ye `--base` ayrıştırmasını ekle** (`--fast` ile çakışma ve taban doğrulaması yapılandırma denetiminden önce); `adr` kontrolü `trace`'ten sonra `sw_verify_run adr '…'` ile.
- [ ] **Step 5:** `sh tests/adr_test.sh && sh tests/verify_test.sh && sh tests/lint_test.sh` → PASS.
- [ ] **Step 6: `docs/design.md` §4'e `adr` ekle, `docs/decisions.md`'ye D-35 yaz** (değişiklik kümesi tanımı, `--no-renames`, bayraksız `verify`'da `adr` yok, `--fast` ile çakışma). Commit: `M3: adr gate and verify --base`.

---

### Task 3: Git hook'ları (AC-M3-01, AC-M3-02)

**Files:**
- Create: `src/hooks/pre-commit`, `src/hooks/pre-push`, `tests/hooks_test.sh`
- Modify: `install.sh`, `src/lib/doctor.sh`, `tests/install_test.sh` (EXPECTED_FILES'a iki hook), `tests/lint_test.sh` (`src/hooks/*` ekle; test yorumuna `AC-M3-09` ekle), `docs/decisions.md`

**Interfaces:**
- Produces (hook'lar, `#!/bin/sh`): kökü kendi yolundan (`$0/../..`) bulur; `"$root/.softwary/local/hooks/<ad>"` çalıştırılabilirse ona `exec "$@"` ile devreder; aksi hâlde `"$root/softwary"` çalıştırılabilir değilse `softwary: ./softwary is missing; rerun install.sh` yazıp 2 ile çıkar (kapı açık kalmaz); aksi hâlde `exec "$root/softwary" verify --fast` (`pre-commit`) ya da `verify` (`pre-push`).
- Produces (`install.sh`): `hooks` yönetilen ağaçlara eklenir, kurulumdan sonra `chmod +x` hook'lara; ayrıca dosya kopyası `cp` yerine `*.new` + `mv -f` ile değiştirir (T6'da çalışan betiğin dosyası üzerine yazılmasın). Kurulumun sonunda `hooks:` satırı basılır. Kural: hedef `git rev-parse --show-toplevel`'a eşit değilse (alt dizin, git değil) hiçbir şey ayarlanmaz ve `hooks: not a git repository root; core.hooksPath not set`; `core.hooksPath` zaten `.softwary/hooks` ise `hooks: core.hooksPath already .softwary/hooks`; başka bir değer varsa `hooks: core.hooksPath is '<x>'; kept`; `git rev-parse --git-path hooks` dizininde `.sample` olmayan dosya varsa `hooks: <dizin>/<ad> is not a sample; kept`; aksi hâlde `git config core.hooksPath .softwary/hooks`.
- Produces (`doctor`): yalnız git deposunda `hooks` satırı: `PASS` ya da `FAIL (core.hooksPath is '<x>', not .softwary/hooks)`, `FAIL (core.hooksPath is not set; run: git config core.hooksPath .softwary/hooks)` (varsa `.git/hooks`'taki örnek olmayan hook adı eklenir), `FAIL (.softwary/hooks/<ad> is not executable)`.

- [ ] **Step 1: Başarısız testleri yaz** (`tests/hooks_test.sh`; gerçek `git commit`/`git push`, uzak: `git init --bare $T/remote.git`, `main` dalı):
  - `test_ac_m3_01_install_sets_hooks_path`: `git config core.hooksPath` = `.softwary/hooks`, iki hook `-x`, `sw doctor` çıktısında `^hooks +PASS`.
  - `test_ac_m3_01_other_hooks_path_kept`: kurulumdan önce `core.hooksPath=.githooks` → değişmez, `^hooks +FAIL \(core.hooksPath is '.githooks'`.
  - `test_ac_m3_01_custom_hook_kept`: kurulumdan önce `.git/hooks/pre-commit` (örnek değil) → `core.hooksPath` boş kalır, doctor satırı `.git/hooks/pre-commit`'i anar; `.sample` dosyaları engel olmaz.
  - `test_ac_m3_01_not_a_repo_root`: hedef, `git init` edilmiş bir dizinin alt dizini → kurulum RC 0, üst deponun `core.hooksPath`'i boş; `git worktree add` ile açılmış (`.git` dosya) hedefte kurulum çökmez ve yol ayarlanır.
  - `test_ac_m3_02_commit_gated_by_verify_fast`: komutlar `true` iken `git commit` başarılı; `conf_set lint false` ile commit reddedilir (RC≠0, `HEAD` değişmedi, çıktıda `lint` `FAIL`).
  - `test_ac_m3_02_push_gated_by_verify`: yalnızca `test = false` iken commit geçer (hızlı anahtarlar sağlam) ama `git push origin main` reddedilir; `test = true` olunca push geçer.
  - `test_ac_m3_02_local_hook_overrides`: `.softwary/local/hooks/pre-commit` (çalıştırılabilir, işaret dosyası yazıp `exit 0`) varken `lint = false` olsa da commit geçer ve işaret dosyası vardır; `local/hooks/pre-push` `exit 1` iken push, `verify` geçse de reddedilir.
  - `test_ac_m3_02_missing_wrapper_fails_closed`: `./softwary` silinir → commit reddedilir, çıktı `./softwary is missing`.
- [ ] **Step 2:** `sh tests/hooks_test.sh` → FAIL.
- [ ] **Step 3: Hook'ları, `install.sh` değişikliklerini ve `doctor` satırını uygula;** `install_test.sh`/`lint_test.sh` listelerini güncelle.
- [ ] **Step 4:** `sh tests/hooks_test.sh && sh tests/install_test.sh && sh tests/doctor_test.sh && sh tests/lint_test.sh` → PASS.
- [ ] **Step 5: `docs/decisions.md`'ye D-36 yaz** (hook devri, kapı kapalı, `core.hooksPath` kuralı, yerel ezme). Commit: `M3: git hooks and hooksPath`.

---

### Task 4: CI ve CODEOWNERS şablonları (AC-M3-05, AC-M3-06)

**Files:**
- Create: `src/templates/github/softwary.yml`, `src/templates/github/CODEOWNERS`, `tests/ci_test.sh`
- Modify: `install.sh` (`src/templates/github/*` → `.softwary/templates/`), `src/lib/doctor.sh`, `tests/lib.sh` (`add_ci`; `setup_repo` tam-kurulum dalında çağırır), `tests/stacks_test.sh` (`run_scenarios` içinde `add_ci`), `tests/install_test.sh` (EXPECTED_FILES), `docs/decisions.md`

**Interfaces:**
- Produces: `softwary.yml`: `on: pull_request` ve `push: branches: [main]`; `actions/checkout@v4` ile `fetch-depth: 0`; araç kurulum adımı `run: UNSET # replace with the commands that install the tools commands.conf uses`; PR adımı `env: BASE_REF: ${{ github.base_ref }}` ile `./softwary verify --base "origin/$BASE_REF"`; push adımı `./softwary verify`. `CODEOWNERS`: `/specs/`, `/architecture/`, `/.softwary/config/`, `/.github/` satırları, sahip `UNSET`.
- Produces (`doctor`): `workflow` satırı: `PASS`; `FAIL (.github/workflows/softwary.yml not found; copy .softwary/templates/softwary.yml)`; `FAIL (… still contains UNSET (line N))`. `CODEOWNERS` satırları (her sorun ayrı satır): `FAIL (.github/CODEOWNERS not found; copy .softwary/templates/CODEOWNERS)`, kapsanmayan her yol için `FAIL (does not cover <yol>/)`, `FAIL (owner is UNSET (line N))`. `UNSET` aramasında `#` ile başlayan satırlar yok sayılır. Bir satır yolu kapsar: deseni (baştaki `/` ve sondaki `/`, `/**` atılarak) yola eşitse ya da desen `*`/`**` ise **ve** satırda en az bir sahip varsa.
- Produces (`tests/lib.sh`): `add_ci` → şablonları `.github/workflows/softwary.yml` ve `.github/CODEOWNERS` olarak kopyalar; `run: UNSET…` → `run: true`, CODEOWNERS'ta `UNSET` → `@owner`.

- [ ] **Step 1: Başarısız testleri yaz** (`tests/ci_test.sh`):
  - `test_ac_m3_05_install_places_templates_not_github`: iki şablon `.softwary/templates/`'te; `.github` yok.
  - `test_ac_m3_05_doctor_reports_missing_files`: yeni kurulumda `^workflow +FAIL \(.*not found` ve `^CODEOWNERS +FAIL \(.*not found`, ayrı satırlarda.
  - `test_ac_m3_05_unset_templates_fail`: şablonlar değiştirilmeden `.github/`'a kopyalanınca `^workflow +FAIL \(.*UNSET` ve `^CODEOWNERS +FAIL \(owner is UNSET`.
  - `test_ac_m3_05_filled_templates_pass`: `add_ci` sonrası iki satır `PASS`, `doctor` RC 0.
  - `test_ac_m3_05_codeowners_coverage`: yalnız `/specs/` ve `/architecture/` sahipli → `does not cover .softwary/config/` ve `does not cover .github/` iki ayrı satır; `specs/**`, `*` biçimleri kapsar; `# owner: UNSET` yorumu sorun sayılmaz; sahipsiz `/specs/` satırı kapsamaz.
  - `test_ac_m3_06_workflow_triggers_and_checkout`: şablonda `pull_request:`, `push:` altında `main`, `fetch-depth: 0`, `BASE_REF: ${{ github.base_ref }}` ve `verify --base "origin/$BASE_REF"` metinleri (`grep -F`).
- [ ] **Step 2:** `sh tests/ci_test.sh` → FAIL.
- [ ] **Step 3: Şablonları yaz, `install.sh` kopyalama döngüsünü ve `doctor` denetimlerini uygula;** `add_ci`'yi `setup_repo`'nun tam-kurulum dalına ve `stacks_test.sh`'a ekle (aksi hâlde M0 `doctor` testleri ve stacks testleri 2 verir).
- [ ] **Step 4:** `sh tests/run.sh` → tüm dosyalar PASS (bu noktada `setup` skill'i ve `upgrade` hariç her şey yeşil olmalı).
- [ ] **Step 5: `docs/decisions.md`'ye D-37 yaz** (`UNSET` işaretleri, kapsama kuralı, push'ta `--base` yok, `BASE_REF` env ile aktarım). Commit: `M3: CI workflow and CODEOWNERS templates`.

---

### Task 5: `setup` skill'i (AC-M3-07)

**Files:**
- Create: `src/skills/setup/SKILL.md`, `tests/skill_test.sh`
- Modify: `docs/decisions.md`; `sync` testlerinden `softwary-setup`'ın görünmesiyle bozulanlar (`sh tests/run.sh` ile bul)

**Interfaces:**
- Produces: `SKILL.md` üst bilgisi yalnızca `name: setup` ve tek satır `description:`; gövde kısa (≈ 60 satırı geçmez), adımlar: (1) `./softwary doctor` ile eksikleri gör; (2) `commands.conf`'u repo manifestlerinden öner, bilmediğini sor, uydurma, `NONE:` yalnız insanın verdiği gerekçeyle; (3) `tools.conf` on/off sor; (4) `risk.conf` `default` ve desenleri sor; (5) kodlu repoda model yoksa `.softwary/templates/system.calm.json`'dan koddan taslak model yaz, `./softwary model validate` ve `./softwary views`, sonra `.softwary/templates/adr.md`'den `status: proposed`, `affects: architecture/model/system.calm.json` olan taban çizgisi ADR'si yaz — `accepted` yapma; (6) `.softwary/templates/softwary.yml` ve `CODEOWNERS`'ı `.github/`'a koy, sahipleri ve araç kurulum adımını sor; (7) `./softwary sync`; (8) `./softwary doctor` geçene kadar tekrarla, sonra insana ADR'yi kabul etmesini ve dal korumasında kod sahibi incelemesini açmasını söyle.

- [ ] **Step 1: Başarısız testleri yaz** (`tests/skill_test.sh`):
  - `test_ac_m3_07_distributed_to_three_tools`: `setup_repo`, `tools_all on`, `sw sync` → `.claude/skills/softwary-setup/SKILL.md`, `.cursor/skills/softwary-setup/SKILL.md`, `.agents/skills/softwary-setup/SKILL.md` var; `sw sync --check` RC 0.
  - `test_ac_m3_07_commands_are_recognised`: kaynak `SKILL.md`'den her `./softwary <komut>` ifadesinin ilk sözcüğü awk ile çıkarılır (`grep -o` POSIX değil); `sh src/bin/softwary help` çıktısının `commands:` altındaki ilk sözcüklerinin içinde olmalı; kümenin boş olmadığı da sınanır.
  - `test_ac_m3_07_names_doctor_adr_template_and_proposed`: gövde `doctor`, `.softwary/templates/adr.md` ve `proposed` içerir.
- [ ] **Step 2:** `sh tests/skill_test.sh` → FAIL.
- [ ] **Step 3: `SKILL.md`'yi yaz.** `install.sh` `src/skills/`'i zaten kurar; `install.sh` değişikliği gerekmez.
- [ ] **Step 4:** `sh tests/run.sh`; `softwary-setup`'ın çıkmasıyla bozulan eski testleri (örn. üretilen dosya kümesini sayanlar) kasıtlı olarak ve yalnızca bu skill'i hesaba katarak düzelt. Beklenen: tümü PASS.
- [ ] **Step 5: `docs/decisions.md`'ye D-38 yaz** (skill'in uydurma yasağı ve ADR kuralı; `help` çıktısı komut listesinin tek kaynağı). Commit: `M3: setup skill`.

---

### Task 6: `upgrade` ve son kapı (AC-M3-08, AC-M3-09)

**Files:**
- Create: `src/lib/upgrade.sh`, `tests/upgrade_test.sh`
- Modify: `install.sh` (`--upgrade`), `src/bin/softwary` (kaynakla, dispatch, usage `upgrade <package-path>`), `docs/decisions.md`

**Interfaces:**
- Produces (`install.sh`): `sh install.sh <repo> [--upgrade]`; `--upgrade` ile kopyalamadan sonra yönetilen köklerde (`.softwary/bin lib rules targets skills agents hooks templates`) plan dışı her dosya `  removed <yol>` basılarak silinir, boşalan dizinler budanır; `.softwary/config`, `local`, `state`, `generated` ve repo kökündeki proje dosyalarına dokunulmaz.
- Produces (`upgrade.sh`): `sw_version_cmp A B` → `-1|0|1`, alanlar sayısal (`N.N.N` değilse `2` ile hata); `sw_upgrade PKG`: `PKG`'de `VERSION`, `install.sh`, `src/bin/softwary` yoksa `upgrade: <yol> is not a softwary package` (2); yeni sürüm kurulu olandan küçükse `upgrade: <yeni> is older than the installed <eski>` (2, hiçbir şey değişmez); aksi hâlde `upgrade: <eski> -> <yeni>` basar, `sh PKG/install.sh "$SOFTWARY_ROOT" --upgrade` çalıştırır (hata → 2), sonunda `exec sh "$SOFTWARY_ROOT/.softwary/bin/softwary" sync` (yeni kodla). Eşit sürüm yeniden uygulanır (`0.0.0 -> 0.0.0`).

- [ ] **Step 1: Başarısız testleri yaz** (`tests/upgrade_test.sh`; yardımcı `make_pkg DIR VERSION`: `install.sh`, `VERSION`, `src/`'yi kopyala, `VERSION`'ı yaz; yola göreli `../pkg` ile de çağır):
  - `test_ac_m3_08_replaces_managed_files_and_runs_sync`: yeni pakette `src/rules/core.md`'ye satır eklenir, sürüm `0.1.0` → RC 0, ilk satır `upgrade: 0.0.0 -> 0.1.0`, `.softwary/VERSION` = `0.1.0`, `.softwary/rules/core.md` yeninin aynısı, `AGENTS.md` bloğu güncel, `sw sync --check` RC 0.
  - `test_ac_m3_08_removes_files_gone_from_new_version`: yeni paket `src/templates/artifacts/review.md`'siz → `.softwary/templates/review.md` silinir, çıktı `removed .softwary/templates/review.md`; yeni pakette eklenen dosya kurulur.
  - `test_ac_m3_08_leaves_project_files_alone`: `snapshot` öncesi/sonrası (`changed_paths`): `.softwary/config/`, `.softwary/local/`, `.softwary/state/`, `architecture/`, `specs/`, `CONTEXT.md` altında değişen yok (`.softwary/generated` ve yönetilen yollar değişebilir).
  - `test_ac_m3_08_version_order_is_numeric`: kurulu `0.9.0`, paket `0.10.0` → RC 0; kurulu `0.10.0`, paket `0.9.0` → RC 2 ve `snapshot` değişmez; kurulu `0.2.0`, paket `0.1.0` → 2; `VERSION` içeriği `abc` → 2.
  - `test_ac_m3_08_not_a_package_exits_2`: repo kendisi, var olmayan yol, boş dizin, argümansız çağrı → her biri RC 2, `snapshot` değişmez.
  - `test_ac_m3_08_sync_failure_is_reported`: `tools.conf` `UNSET` iken `upgrade` RC 2 verir (yönetilen dosyalar yine de yenilenmiştir).
  - `test_ac_m3_08_hooks_path_redirected`: `core.hooksPath` boşken `upgrade` sonrası `.softwary/hooks` ayarlıdır.
- [ ] **Step 2:** `sh tests/upgrade_test.sh` → FAIL.
- [ ] **Step 3: `install.sh --upgrade`'i, `upgrade.sh`'ı ve dispatch/usage'ı uygula.**
- [ ] **Step 4: AC-M3-09 kapısı.** `sh tests/run.sh` → `all N test files passed`; `lint_test.sh` yeni dosyaları (`src/hooks/*`, `src/lib/*.sh`, `tests/*.sh`) kapsadığından `shellcheck` temiz. M0–M2 testlerinden hiçbiri atlanmadı, silinmedi ya da zayıflatılmadı (`git diff main -- tests/` ile yalnız yardımcı ve ekleme değişikliği olduğunu doğrula).
- [ ] **Step 5: `docs/decisions.md`'ye D-39 yaz** (yönetilen küme = `install.sh` planı, `--upgrade` silme kuralı, sürüm sırası, `exec sync`, `mv` ile değiştirme gerekçesi). Commit: `M3: upgrade`, ardından `git push -u origin claude/dreamy-dirac-rmwxt8`.

---

## Self-review

- **Spec kapsamı:** AC-01/02 → T3; AC-03 → T1; AC-04 → T2; AC-05/06 → T4; AC-07 → T5; AC-08 → T6; AC-09 → T6 Step 4 (+ T3'te `lint_test` listesi). Kapsam maddeleri: `setup` skill T5, hook'lar T3, şablonlar T4, `trace`+`verify --base` T1/T2, `upgrade` T6. Boşluk yok.
- **Karar gerektiren belirsizlikler** (spec "yapıcının takdiri" ya da sessiz): bayraksız `verify`'da `adr` çalışmaz (T2), `affects` repo yoludur (T1), yönetilen küme `install.sh` planıdır (T6), iş akışı `push`'ta `--base` kullanmaz (T4). Hepsi `docs/decisions.md`'ye yazılacak; itiraz varsa kod yazılmadan değişir.
- **Tip/ad tutarlılığı:** `write_adr`, `commit_all` (T1) T2–T6'da aynı adla; `sw_base_commit`/`sw_changed_since` yalnız T2'de tanımlı ve kullanılıyor; `add_ci` (T4) T5/T6 testlerinde `setup_repo` üzerinden gelir.
