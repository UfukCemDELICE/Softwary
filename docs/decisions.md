# Kararlar

Belgelerde karara bağlanmamış konularda `docs/design.md` ilkelerine göre verilen kararlar. Bir karar değişirse önce bu dosya güncellenir.

## M0

| No | Konu | Karar | Dayanak |
| --- | --- | --- | --- |
| D-01 | `commands.conf` biçimi | `#` ile başlayan ve boş satırlar yok sayılır; boşluklar kırpılır; anahtar `[a-z][a-z0-9_]*`. Değer ilk `=`'den sonrasıdır. Boş değer, gerekçesiz `NONE`/`NONE:` ve yinelenen anahtar bozuk satırdır: çıkış 2, `commands.conf:<satır>:` ile bildirilir. Bütün bozuk satırlar birlikte listelenir. | İlke 4 |
| D-02 | Tanınmayan anahtar | `verify` 2 ile durur ve `UNKNOWN <anahtar> (line N)` basar. Yazım hatası (`lnit`) bir kontrolü sessizce devre dışı bırakamaz. | İlke 4 |
| D-03 | Dosyada hiç olmayan zorunlu anahtar | `UNSET` sayılır. | İlke 4 |
| D-04 | İsteğe bağlı kontroller | `contract_check`, `arch_check` yoksa ya da `UNSET` ise `verify` `SKIP (not configured)` satırı basar; gizlenmez. `run`, `deploy`, `bootstrap` `verify` tarafından çalıştırılmaz. `test_paths`, `src_paths` tanınan ayar anahtarlarıdır, şablonda yer almaz. | İlke 4, spec kapsam dışı notu |
| D-05 | Kontrol sırası | `format_check`, `lint`, `typecheck`, `test`, `build`, `contract_check`, `arch_check`, `security`. | design §4 "ucuzdan pahalıya" |
| D-06 | `--fast` ve `UNSET` | `--fast` yalnızca çalıştıracağı üç anahtarın `UNSET` olmasını hata sayar. Bozuk satır ve tanınmayan anahtar yine 2 ile durur. | İlke 4 (atlanan kontrol yok, kapsam dışı kontrol var) |
| D-07 | Satır biçimi | Ad önde, sabit genişlikte: `lint            PASS (3s)`, `FAIL (3s)`, `SKIP (<gerekçe>)`. Süre tam saniyedir (POSIX `date +%s`). Sonda tek özet satırı. `doctor` aynı biçimi kullanır. | İlke 7, POSIX sınırı |
| D-08 | Kayıtlar | Her kontrolün tam çıktısı `.softwary/state/logs/verify-<anahtar>.log` dosyasına yazılır ve her çalıştırmada üzerine yazılır. Hatada son 20 satır, kayıt yolu ve çıkış kodu basılır. | İlke 7, `state/` git dışı |
| D-09 | Komutların çalıştırılması | Repo kökünde `sh -c`, stdin `/dev/null`. Repo kökü sarmalayıcının bulunduğu dizindir; alt dizinden çağrı aynı sonucu verir. | İlke 3 |
| D-10 | Kurulum | Hedef var olan bir dizin olmalı (yoksa 2). Önce yazılacak dosyaları listeler, sonra onay sormadan yazar. Yönetilen dosyaların üzerine yazar; var olan `commands.conf` korunur ve listede `(exists, kept)` görünür. Git reposu şartı yoktur; bunu `doctor` bildirir. `.softwary/.gitignore` `state/`'i dışlar. Kullanıcısı olmayan `local/`, `risk.conf`, `tools.conf`, `templates/` M0'da kurulmaz. | design §3, İlke 7 |
| D-11 | `doctor` | Kontrol başına `PASS`/`FAIL (<neden>)` satırı; sorun yoksa 0, varsa 2. `git`, `jq`, git reposu, sarmalayıcı, `commands.conf` varlığı ve biçimi, `UNSET` zorunlu anahtarlar, tanınmayan anahtarlar ayrı satırlarda. | design §4 çıkış kodları |
| D-12 | Örnek repolar | Python (`py_compile`, `unittest`) ve Node (`node --check`, `npm test`). Araç yoksa testler atlanmaz, başarısız olur. İki stack'in çıkış kodları ve durum satırları birebir karşılaştırılır. | İlke 4 |
| D-13 | Test düzeneği | Saf POSIX `sh`, ek bağımlılık yok. Tek komut: `sh tests/run.sh`. Test fonksiyonları `test_` ile başlar ve üstlerindeki yorum kabul kriteri kimliğini taşır. `shellcheck` yoksa test başarısız olur. | design §3, §5 izlenebilirlik, İlke 4 |
| D-14 | Shellcheck istisnaları | Yalnızca gerekçeli ve yerel `disable` direktifleri: dosyalar arası paylaşılan değişkenler (SC2034), `run_tests` tarafından çağrılan test fonksiyonları (SC2329) ve kasıtlı sözcük bölme/tek tırnak. | AC-M0-10 |

## M1 öncesi varsayım doğrulaması (2026-11-14)

design §9'daki araç varsayımları. Claude Code resmî belgeden doğrudan okundu. Cursor ve Codex önce arama özetlerinden alındı, M1 başında (Hazırlık 2) resmî sayfalardan doğrudan teyit edildi; Codex belgeleri `learn.chatgpt.com/docs/` adresine taşınmış.

| Varsayım | Sonuç | Kaynak |
| --- | --- | --- |
| Claude Code skill'leri `.claude/skills/<ad>/SKILL.md`'den yükler | Doğru. Hiçbir alan zorunlu değil; Agent Skills standardı dışında `name`, `description` taşınabilir. | code.claude.com/docs/en/skills |
| Cursor skill'leri `.cursor/skills/`'ten yükler | Doğru. Proje düzeyinde `.agents/skills/`'i de resmî olarak okur; uyumluluk için `.claude/skills/`, `.codex/skills/`'i de. `name` zorunlu, `[a-z0-9-]` ve klasör adıyla aynı olmalı; `description` zorunlu. | cursor.com/docs/skills |
| Codex skill'leri `.agents/skills/`'ten yükler | Doğru; çalışma dizininden repo köküne kadar her `.agents/skills`. `name` ve `description` zorunlu. Aynı adlı iki skill birleştirilmez, ikisi de görünür. | learn.chatgpt.com/docs/build-skills |
| Cursor subagent yolu ve biçimi | `.cursor/agents/<ad>.md`, YAML üst bilgi ve gövde. `name` ve `description` isteğe bağlı (arama özeti zorunlu demişti, yanlış). `.claude/agents/` ve `.codex/agents/`'ı da okur; aynı adda `.cursor/` önceliklidir. | cursor.com/docs/subagents |
| Codex subagent yolu ve biçimi | `.codex/agents/<ad>.toml`, dosya başına bir agent; zorunlu alanlar `name`, `description`, `developer_instructions`. | learn.chatgpt.com/docs/agent-configuration/subagents |
| `CLAUDE.md`, `AGENTS.md`'yi içe aktarabilir | Doğru: `@AGENTS.md` (en fazla 4 düzey). Ayrıca Claude Code ≥ 2.1.277, `CLAUDE.md` yoksa `AGENTS.md`'yi doğrudan okur; `CLAUDE.md` varsa okumaz. Bu yüzden `CLAUDE.md` bloğu gerekli kalır. | code.claude.com/docs/en/memory |
| Cursor `AGENTS.md` okur | Doğru; kökte ve alt dizinlerde. | cursor.com/docs/rules |
| Codex `AGENTS.md` okur | Doğru; kökten çalışma dizinine kadar birleştirir, varsayılan sınır 32 KiB. | learn.chatgpt.com/docs/agent-configuration/agents-md |
| CALM metadata, git hook yolu | M1'i etkilemiyor; M2 ve M3 öncesi doğrulanacak. | — |

## M1

| No | Konu | Karar | Dayanak |
| --- | --- | --- | --- |
| D-15 | Cursor'da skill tekrarı | Her hedef yalnızca kendi klasörüne yazar (design §8 tablosu). Cursor `.claude/skills/` ve `.agents/skills/`'i de okuduğu için aynı skill birden çok kez görünebilir; bu bilerek kabul edildi. Hedefler birbirinden bağımsız kalır, yeni araç tek bir hedef scriptiyle eklenir. | İnsan kararı (2026-11-14), design §8 |
| D-16 | `tools.conf` varsayılanı | `install.sh` her aracı `UNSET` yazar; `sync` her araç açıkça seçilene kadar 2 ile durur. | İlke 4 |
| D-17 | `tools.conf` biçimi | M0 ayrıştırıcısı (`sw_kv_load`) ortak. Anahtar `[a-z][a-z0-9-]*` (hedef scriptinin adı), değer `on`, `off` ya da `UNSET`. Tanınan araçlar `targets/` ve `local/targets/` altındaki scriptlerdir. Eksik araç, tanınmayan araç, geçersiz değer ve `UNSET` ayrı ayrı ve satır numarasıyla 2 koduyla bildirilir. | İlke 4, AC-M1-09, AC-M1-10 |
| D-18 | `AGENTS.md` bloğu | Hangi araçlar açık olursa olsun `sync` çekirdeği yazar: `CLAUDE.md` onu içe aktarır, Cursor ve Codex onu okur. Hedefler bu yolu üretemez (iki kaynak aynı yolu üretirse 2). | design §8, İlke 2 |
| D-19 | Hedef scripti sözleşmesi | `sh <hedef>.sh SRC FILES BLOCKS`; `SRC` doğrulanmış kaynaklar, hedef yalnızca `FILES` (tam dosyalar) ve `BLOCKS` (blok içerikleri) altına repo yoluyla yazar. Yardımcılar `lib/target.sh`'dedir. Aynı yolu iki hedef üretirse 2. | AC-M1-10, design §8 |
| D-20 | Üretilen dosyaların izlenmesi | `.softwary/generated` (commit'lenir) her dosya ve blok için `cksum` ve yolu tutar. Silme yalnızca buradaki yollara uygulanır; manifestte olmayan bir dosyanın üzerine yazılmaz (2). `cksum` ile "elle değiştirilmiş" ve "kaynak değişti" ayrılır. Önce her şey geçici dizinde üretilir, sonra karşılaştırılır; `sync` ve `sync --check` aynı planı kullanır. | AC-M1-07, AC-M1-08, İlke 2 |
| D-21 | Bloklar | İşaretçiler `<!-- softwary:begin: … -->` ve `<!-- softwary:end -->`. Blok yoksa bir boş satırla sona eklenir; varsa yerinde değişir. Bozuk ya da birden fazla işaretçi 2 ile reddedilir ve dosyaya dokunulmaz. Blok kaldırılınca önündeki boş satır da gider; geriye bir şey kalmazsa dosya silinir. | AC-M1-02, AC-M1-07 |
| D-22 | Kaynak üst bilgisi | Yalnızca tek satırlık `name` ve `description`; `name` klasör ya da dosya adına eşit, `[a-z0-9-]`. Skill adı `softwary-<ad>` olur; agent adı değişmez. Üretilen Markdown'a üst bilginin altında, TOML'a ilk satırda "do not edit" notu eklenir. YAML tırnakları TOML'a geçerken açılır. Agent gövdesi boş olamaz. | design §8, Cursor ad kuralı, İlke 7 |
| D-23 | `verify` ve `--fast` | `verify`'ın ilk kontrolü `sync` (`sync --check`); `tools.conf` sorunları diğer yapılandırma eksikleriyle birlikte 2 ile bildirilir. `--fast` bu kontrolü çalıştırmaz ve `tools.conf`'u istemez (D-06). | design §4, AC-M0-06 |
