# V9 Cursor ve sürüm — Uygulama planı

**Goal:** `docs/specs/V9.md`'deki AC-V9-01..13'ü karşılamak:
- araç başına model çevirisi ve ayrım kuralı;
- araçtan bağımsız skill ve ajanlar;
- sürüm arşivi, arşivden kurulum ve yükseltme;
- `uninstall` ve `version`;
- telemetri denetimi;
- İngilizce kullanıcı belgeleri;
- `0.1.0`.

**Architecture:**
- **Yeni dosyalar:**
  - `src/lib/uninstall.sh`: listeleme ve silme.
  - `tools/release.sh`: paketin geliştirme aracı; kurulmaz.
- **Var olan dosyalara ekler:**
  - `src/lib/loopconf.sh`: `sw_models_load` çeviri satırlarını okur; `sw_models_get AGENT TOOL` eklenir.
  - `src/lib/sync.sh` ve `src/lib/target.sh`: Cursor üst bilgisinde `model`, Codex TOML'unda `model`.
  - `src/targets/cursor.sh` ve `src/targets/codex.sh`.
  - `src/lib/doctor.sh` ve `src/lib/run.sh`: ayrım kuralı.
  - `install.sh`: `--archive`, `--sha256`.
  - `src/lib/upgrade.sh`: arşiv.
  - `src/bin/softwary`: `uninstall`, `version`, `help`.
- **Arşiv açma:**
  - Tek bir yardımcı ile yapılır: `install.sh` içinde, `upgrade` onu çağırır.
  - SHA-256 için `sha256sum` ya da `shasum -a 256`; ikisi de yoksa 2. `formal.sh`'teki `sw_formal_sha256` aynı mantığı kullanır, ama `install.sh` paketten önce çalıştığı için kendi kopyasını taşır.

**Tech Stack:** POSIX `sh`, `git`, `jq`, `tar`, `gzip`, `shellcheck`.

**Spec:** `docs/specs/V9.md` (approved). Bağlam:
- `docs/design.md` §8, §10, §12, §13;
- `docs/decisions.md`:
  - M1 varsayım tablosu;
  - D-15..D-24 (`sync`, bloklar, manifest);
  - V2'deki `models.conf` kararları;
  - `upgrade` kararları;
  - D-150 (`install.sh` koruması).

## Global Constraints

- Scriptler POSIX `sh`; yeni çalışma zamanı bağımlılığı yok. `tar` ve `gzip` yalnızca arşiv yolunda gerekir.
- `shellcheck -s sh -x` temiz; çıkış kodları `0/1/2`.
- Paket içeriği ve `README.md`/`docs/guide/` İngilizcedir. `docs/` altındaki geliştirme kaydı Türkçedir.
- Her test `test_` ile başlar ve üstündeki yorum kriter kimliğini taşır. Önce test yazılır ve kırmızı koşu commit mesajına not edilir (`red: <dosya> FAIL (<n> failing)`), sonra kod.
- Kararlar `docs/decisions.md`'ye "## V9" başlığı altında D-189'dan başlayarak yazılır; sapmalar kendi satırına.
- Dal `claude/zen-ramanujan-jy9sc6`; push ve PR'ı orkestratör yapar.
- Hiçbir script etiket atmaz, `git push` etmez, bir şey yüklemez ya da yayımlamaz.

## Kararlar (decisions.md'ye girer)

- **D-189 Spec onayı:** V9 spec'i kullanıcı isteğiyle yazıldığı oturumda `approved` yapıldı.
- **D-190 Varsayım teyidi (Hazırlık 3):**
  - Cursor alt ajan üst bilgisinde `model` alanı ve aldığı değerler.
  - Codex özel ajan TOML'unda `model` alanı.
  - Kaynak adresleri ve okunma tarihi.
- **D-191 Model çevirisi:** *insan onaylı (2026-11-18): araç başına ad çevirisi.*
  - **Satır biçimi:** `<araç>: <sınıf> = <kimlik>`. Araç `tools.conf`'taki adlardır (`claude-code`, `cursor`, `codex`). Sınıf, ajan satırlarında geçen bir değerdir.
  - **Hatalar (`SW_MODELS_ERRORS`'a satır):** bilinmeyen araç, kullanılmayan sınıfın çevirisi, yinelenen çeviri, boş ya da `UNSET` kimlik.
  - **Claude Code:** çeviri yoksa sınıf adı yazılır.
  - **Şablon:** `models.conf` çeviri satırlarını yorum olarak açıklar; şablona etkin çeviri satırı yazılmaz, çünkü proje dosyasıdır ve kurulumda üzerine yazılmaz.
- **D-192 Ayrım kuralı:** her açık araç için `reviewer` ve `approver` çevrilmiş kimliği `implementer`'ınkiyle karşılaştırılır. Karşılaştırma tam dize eşitliğidir; büyük-küçük harf korunur.
- **D-193 Araçtan bağımsız metin:** yasak sözcük listesi `tests/skill_test.sh`'te tutulur:
  - araç adları: `Task tool`, `Agent tool`, `SendMessage`, `subagent_type`, `TodoWrite`;
  - ürün adları: `Claude Code`, `Cursor`, `Codex`.

  Liste `src/skills` ve `src/agents`'a uygulanır. `src/targets/*` ve `docs/guide/` muaftır.
- **D-194 Sürüm arşivi:** *insan onaylı (2026-11-18): klon ve sürüm arşivi, `curl | sh` yok.*
  - **Üretim:** `git archive --format=tar --prefix=softwary-<v>/ HEAD -- <yollar> | gzip -n -9 > dist/...`. `gzip -n` zaman damgasını yazmaz; `git archive` commit zamanını kullanır, bu yüzden aynı commit'ten aynı bayt çıkar.
  - **Yollar:** `install.sh`, `VERSION`, `src/`, `README.md`, `LICENSE`, `CHANGELOG.md`.
  - **`SHA256SUMS`:** `sha256sum` biçiminde.
  - **`dist/`:** `.gitignore`'a girer.
- **D-195 Arşivden kurulum:**
  - `install.sh`, `--archive` ile verilen arşivi `mktemp -d`'ye açar; çıkışta (hata dahil) siler.
  - Açılan dizinde tek bir `softwary-*` kökü ve onun içinde `VERSION`, `install.sh` ve `src/bin/softwary` olmalıdır.
  - Sonra açılan dizindeki `install.sh` hedefe kurar; arşivin kendi sürümünün kurulumu.
  - `upgrade <tar.gz> --sha256 <özet>` aynı açma yardımcısıyla dizini bulur ve bugünkü `upgrade` yoluna devam eder.
- **D-196 `uninstall`:** *insan onaylı (2026-11-18): paket silinir, projeninki korunur.*
  - **Ne silinir:** yönetilen dosya listesi `install.sh`'in planıyla aynı kümedir. `uninstall` onu kurulu paketten (`.softwary/` altındaki yönetilen ağaçlar) hesaplar.
  - **Üretilen dosyalar:** `.softwary/generated` manifestindeki yollar ve `cksum` değerleri kullanılır; uyuşmayan dosya `kept (changed by hand)` olarak bildirilir.
  - **Bloklar:** `sync`'in blok kaldırma yardımcısıyla kaldırılır.
  - **Koşu ve işler:** etkin koşu ya da `done`/`abandoned` olmayan bir iş varsa ret.
  - **Sıra:** önce üretilen dosyalar, sonra yönetilen dosyalar, en son sarmalayıcı. Silme çalışan scriptin kendi dosyalarını da kaldırır: `uninstall` gereken her şeyi önce belleğe alır, son adımda kendi kodunu silen bir `exec sh -c` kullanır ya da silme listesini yazıp yönetilen ağaçları en sonda siler. Yapıcı birini seçer ve kararda yazar.
  - **Boşalan dizinler:** silinir; `.softwary/` kalır.
- **D-197 Telemetri denetimi:** `tests/network_test.sh`, `src/` ve `install.sh`'te `curl`, `wget`, `nc `, `ncat`, `/dev/tcp` ve `http://`/`https://` geçen satırları bir izin listesiyle (dosya:fonksiyon) karşılaştırır. İzin listesi:
  - `formal.sh` `sw_formal_install` (indirme ve URL sabiti);
  - yorum satırları;
  - `README` bağlantısı gibi metinler.
- **D-198 Belgeler:** *insan onaylı (2026-11-18): kullanıcı belgeleri İngilizce; geliştirme kaydı Türkçe kalır.* `docs/guide/commands.md` `help` çıktısından elle yazılır; test her komut adının ve alt komutun belgede geçtiğini denetler. Belgeler İngilizce olduğu için design §10'daki "paketin kendi belgeleri Türkçedir" cümlesi güncellenir: kullanıcı belgeleri İngilizce, geliştirme kaydı Türkçe.
- **D-199 Sürüm:** `VERSION` `0.1.0`. `CHANGELOG.md` [Keep a Changelog](https://keepachangelog.com) biçimindedir; tek bölüm `## 0.1.0` ve tarih yok. Tarihi, etiketi atarken insan yazar; `release.sh` tarihsiz başlığı kabul eder.
- **D-200 Test düzeneği:**
  - `tests/models_test.sh`'e çeviri testleri.
  - Yeni dosyalar:
    - `tests/release_test.sh`;
    - `tests/install_archive_test.sh`;
    - `tests/uninstall_test.sh`;
    - `tests/network_test.sh`;
    - `tests/docs_test.sh`;
    - `tests/release_e2e_test.sh`.
  - Sürümü `0.0.0` bekleyen eski testler `VERSION`'dan okuyacak biçimde güncellenir ve kararda listelenir.

## Review Focus

1. **`uninstall`:**
   - Projeye ait hiçbir dosyayı silmemeli: `config/`, `state/`, `local/`, yapıtlar ve `AGENTS.md`'nin blok dışı içeriği.
   - Elle değiştirilmiş üretilen dosyaya dokunmamalı.
   - `--yes` olmadan tek bayt yazmamalı.
   - Paketin olmayan bir `softwary` dosyasını silmemeli (T3).
2. **Arşivden kurulum:**
   - Özet uyuşmazlığında, kötü arşivde ya da kökü birden çok olan ya da `../` içeren arşivde hiçbir şey yazmamalı.
   - Açma dizini her durumda silinmeli (T2).
3. **Deterministiklik:** iki `release.sh` çalıştırması aynı SHA-256'yı vermeli (T2).
4. **Ayrım kuralı:** her açık araç için ayrı hesaplanmalı; kapalı aracın çevirisi yoksa hata olmamalı (T1).
5. **Yasak sözcük denetimi:** skill metninde geçerli kullanımları kırmamalı; örneğin "the tool" genel sözcüğü (T1).

---

### Task 1: Model çevirisi, ayrım kuralı, araçtan bağımsız metin (AC-V9-01..04)

**Files:**
- Modify:
  - `src/lib/loopconf.sh`, `src/lib/sync.sh`, `src/lib/target.sh`;
  - `src/targets/cursor.sh`, `src/targets/codex.sh`;
  - `src/lib/doctor.sh`, `src/lib/run.sh`;
  - `src/templates/models.conf`;
  - `src/skills/*/SKILL.md` ve `src/agents/*.md` (yalnızca yasak sözcük geçiyorsa);
  - `tests/models_test.sh`, `tests/sync_test.sh`, `tests/skill_test.sh`.

- [ ] Hazırlık 3: Cursor ve Codex `model` alanlarını resmî belgeden teyit et ve D-190'ı yaz. Teyit edilemezse dur ve raporla.
- [ ] `test_ac_v9_01_*`:
  - çeviri okunur;
  - açık araçta eksik çeviri `doctor` FAIL ve `run start` 2;
  - kapalı araçta eksik çeviri sorun değil;
  - bilinmeyen araç, yinelenen çeviri, `UNSET` kimlik;
  - Claude Code'da çevirisiz sınıf adı.
- [ ] `test_ac_v9_02_*`:
  - `.cursor/agents/reviewer.md`'de `model:`;
  - `.codex/agents/reviewer.toml`'da `model =`;
  - `models.conf` bozukken alan yok;
  - `sync --check` güncel.
- [ ] `test_ac_v9_03_*`: Cursor'da reviewer ve approver uygulayıcıyla aynıysa FAIL; Claude Code kuralı aynen.
- [ ] `test_ac_v9_04_*`: yasak sözcükler skill ve ajanlarda yok.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 2: Sürüm arşivi, arşivden kurulum ve yükseltme, `version` (AC-V9-05, 06, 08, 11)

**Files:**
- Create: `tools/release.sh`, `tests/release_test.sh`, `tests/install_archive_test.sh`.
- Modify: `install.sh`, `src/lib/upgrade.sh`, `src/bin/softwary`, `VERSION`, `.gitignore` (`dist/`), `tests/upgrade_test.sh` (gerekirse).

- [ ] `test_ac_v9_05_*`:
  - `VERSION` uyuşmazlığı, `CHANGELOG` eksik bölüm ve kirli ağaç → 1 ve `dist/` yok;
  - temiz → arşiv ve `SHA256SUMS`;
  - iki çalıştırma aynı özet;
  - arşivde `tests/` ve `docs/` yok, `README.md`, `LICENSE` ve `CHANGELOG.md` var;
  - etiket yok.
- [ ] `test_ac_v9_06_*`:
  - doğru özetle kurulum;
  - yanlış özet, `--sha256` yok, paket olmayan arşiv, iki kök ve `../` yolu → 2 ve hedefte değişiklik yok;
  - geçici dizin kalmaz;
  - `upgrade` arşivle;
  - dizin yolu hâlâ geçer.
- [ ] `test_ac_v9_08_version`, `test_ac_v9_11_*`: `0.0.0`'dan `0.1.0`'a geçiş ve `0.1.0`'dan inmenin reddi.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 3: `uninstall` ve telemetri denetimi (AC-V9-07, 09)

**Files:**
- Create: `src/lib/uninstall.sh`, `tests/uninstall_test.sh`, `tests/network_test.sh`.
- Modify: `src/bin/softwary`.

- [ ] `test_ac_v9_07_*`:
  - liste ve `--yes`'siz hiçbir değişiklik yok;
  - `--yes` sonrası kalanlar tam olarak projeninkiler;
  - `AGENTS.md` blok dışı içerik korunur, yalnız blok olan `CLAUDE.md` silinir;
  - elle değişmiş üretilen dosya kalır;
  - `core.hooksPath` temizlenir, başka bir değer korunur;
  - açık iş ya da etkin koşu varsa 1;
  - yeniden `install.sh` ile kurulup `sync` temiz.
- [ ] `test_ac_v9_09_*`: izin listesi dışı ağ çağrısı yok; tek bir `curl` satırı eklenmiş bir kopyada test kırmızı.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 4: Belgeler ve sürüm (AC-V9-10)

**Files:**
- Create:
  - `README.md`, `LICENSE`, `CHANGELOG.md`;
  - `docs/guide/install.md`, `docs/guide/quickstart.md`, `docs/guide/commands.md`, `docs/guide/concepts.md`, `docs/guide/tools.md`;
  - `tests/docs_test.sh`.
- Modify: `docs/design.md` (§10 belge dili cümlesi; §12'ye model çevirisi satırı).

- [ ] `test_ac_v9_10_*`:
  - dosyalar var;
  - `LICENSE` MIT metni ve sahip;
  - `CHANGELOG.md`'de `## 0.1.0`;
  - `commands.md` `help`'teki her komutu anar, olmayanı anmaz;
  - göreli bağlantılar çözülür;
  - stack sözcük denetimi;
  - `README.md` telemetri cümlesi.
- [ ] Belgeler kullanıcının diliyle yazılır: kısa cümle, örnek komut, her kavram bir kez. Türkçe belgelerden çeviri değil, kullanıcıya göre yeniden yazım.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 5: Uçtan uca test, kararlar ve son denetim (AC-V9-12, 13)

**Files:**
- Create: `tests/release_e2e_test.sh`.
- Modify: `docs/decisions.md`, `docs/roadmap.md`, `docs/sources.md` (gerekirse).

- [ ] `test_ac_v9_12_*`: spec'teki akış, tek testte ya da adım başına bir testte.
- [ ] Bütün suite, `shellcheck` ve mutasyon denetimi: her yeni kural bir kez bozulur ve ilgili test `SW_TEST_ONLY` ile kırmızı görülür; kararlara bir satır.
- [ ] Kararlar ve belgeler:
  - `decisions.md` "## V9": D-189..D-200, sapmalar, değişen eski testler;
  - `roadmap.md`'de V9 tamamlandı notu; insanın etiket ve yayın adımları tek satırda.
- [ ] Commit.

## AC → test eşlemesi

| AC | Test |
| --- | --- |
| AC-V9-01..03 | `models_test.sh`, `sync_test.sh` |
| AC-V9-04 | `skill_test.sh` |
| AC-V9-05 | `release_test.sh` |
| AC-V9-06, 08, 11 | `install_archive_test.sh`, `upgrade_test.sh` |
| AC-V9-07 | `uninstall_test.sh` |
| AC-V9-09 | `network_test.sh` |
| AC-V9-10 | `docs_test.sh` |
| AC-V9-12 | `release_e2e_test.sh` |
| AC-V9-13 | bütün suite |
