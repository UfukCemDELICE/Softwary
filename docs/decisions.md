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

## M2 öncesi varsayım doğrulaması (2026-11-14)

Şema `github.com/finos/calm-schema` reposundan (`schema/core.json`, `$id` `https://calm.finos.org/release/1.3/meta/core.json`) doğrudan okundu; `calm.finos.org` bu ortamdan erişilemedi. Şema kaynağı `finos/architecture-as-code`'dan bu repoya taşınmış.

| Varsayım | Sonuç | Kaynak |
| --- | --- | --- |
| CALM metadata'sı `paths`, `risk`, `status` alanlarına izin verir | Doğru. Güncel sürüm 1.3. Düğümün `metadata`'sı ya `additionalProperties: true` olan bir nesne ya da nesne dizisidir. Düğümde zorunlu alanlar `unique-id`, `node-type`, `name`, `description`; ilişkide `unique-id`, `relationship-type` ve `interacts`, `connects`, `deployed-in`, `composed-of`, `options` türlerinden tam biri. `connects` uçları `node` ve isteğe bağlı `interfaces` taşır. | github.com/finos/calm-schema `schema/core.json`, `schema/interface.json` |

## M3 öncesi varsayım doğrulaması (2026-11-14)

`git-scm.com` bu ortamdan erişilemedi; belge git'in kendi reposundan (`github.com/git/git`, `Documentation/`) doğrudan okundu ve yerelde git 2.43 ile denendi.

| Varsayım | Sonuç | Kaynak |
| --- | --- | --- |
| Git hook yolu repodaki bir klasöre yönlendirilebilir | Doğru: `core.hooksPath` (git 2.9'dan beri). Göreli yol, hook'un çalıştığı dizine, yani çıplak olmayan repoda çalışma ağacının köküne göre çözülür; çalıştırma izni olmayan hook yok sayılır. Ayar yerel yapılandırmadır, klonla gelmez: her klonda ayrıca yapılmalı ve `doctor` denetlemelidir. Ayarlanınca `.git/hooks` artık okunmaz. Denemede `core.hooksPath=.softwary/hooks` ile `pre-commit` alt dizinden yapılan commit'te de çalıştı ve commit'i durdurdu. | `Documentation/config/core.adoc`, `Documentation/githooks.adoc`, `Documentation/RelNotes/2.9.0.adoc` |

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

## M2

| No | Konu | Karar | Dayanak |
| --- | --- | --- | --- |
| D-24 | Şablonlar ve kurulum | Şablonlar `src/templates/artifacts/`'tan `.softwary/templates/`'e kurulur (yönetilen). `risk.conf` projeye aittir, yoksa `default = UNSET` ile oluşturulur. Kurulum `architecture/`, `specs/` ve `CONTEXT.md` oluşturmaz. Doldurulması gereken alanlar `UNSET` ya da `NNN` taşır, böylece doldurulmamış şablon denetimden geçmez. İnceleme ve `CONTEXT.md` şablonlarının M2'de denetleyicisi yoktur. | İlke 4, design §3 |
| D-25 | Üst bilgi | İlk satır `---`, sonra `anahtar: değer` satırları (anahtar `[a-z_]+`), kapanış `---`. Liste değerleri virgülle ayrılır. Bilinmeyen alan, yinelenen alan, eksik alan, boş olmaması gereken boş alan ve `UNSET` değer ayrı ayrı bildirilir. Spec: `id title status risk model contracts` (ilk dördü boş olamaz). Dilim: `id spec goal acs depends_on touches status` (`depends_on`, `touches` boş olabilir). | design §5, İlke 4 |
| D-26 | Kriterler ve test araması | Kriter kimliği `AC-NNN-NN`. Spec'in kriterleri, gövdesinde geçen `AC-<id>-NN` kimlikleridir. Test araması `test_paths`'teki (boşlukla ayrılmış, repo köküne göre, var olmalı) dosyalarda `find` ve `grep -E 'AC-…([^0-9]\|$)'` ile yapılır; `grep -r` ve `-o` POSIX olmadığı için kullanılmaz. | Yol haritası M2, design §3 |
| D-27 | `trace` kuralları | Spec yoksa geçer. Dilimi olmayan spec'te kapsama aranmaz. Onaylanmamış (`draft`) spec'in dilimi hatadır. `test_paths` yalnızca `review` ya da `done` dilim varken istenir; yoksa ya da yolu bulunamazsa 2. Sözcük sınırı tüm dosyada `wc -w` ile 600. Açık soru, `## Open questions` başlığı altındaki herhangi bir liste maddesidir. Model ya da sözleşme alanı varken model dosyası yoksa sorun olarak bildirilir. | design §5, İlke 1 ve 4 |
| D-28 | `model validate` | `jq` ile (1.6 uyumlu): geçerli JSON, boş olmayan `nodes`, düğümde dört zorunlu alan, ilişkide `unique-id` ve beş türden tam biri, `interacts`/`connects`/`deployed-in`/`composed-of` başvurularının ve `connects` arayüzlerinin varlığı, düğüm, arayüz ve ilişkiler arasında tekil `unique-id`, `metadata` biçimi ve softwary alanları. `options` türünün içi denetlenmez. Dizi biçimindeki `metadata` sırayla birleştirilir. `paths` olan düğümde `risk` ve `status` zorunlu. Herhangi bir yerdeki `"UNSET"` dizgesi bildirilir. Tam JSON Schema doğrulaması kapsam dışı; isteyen proje `calm` CLI'yi `arch_check`'e koyabilir. | İlke 4, CALM 1.3 |
| D-29 | `views` | Tek dosya: `architecture/views/system.mmd`, `flowchart LR`. Düğüm kimlikleri model sırasıyla `n1..nN` (CALM kimlikleri Mermaid'de sorun çıkarabilir). Aktör yuvarlak, veritabanı silindir. Kenarlar: `interacts` aktörden düğüme, `connects` kaynaktan hedefe ve `protocol` etiketiyle, `composed-of` kapsayandan parçaya, `deployed-in` düğümden kapsayana (noktalı). `options` ilişkileri desen seçimidir, yorum satırı olarak listelenir. Geçersiz modelde görünüm yazılmaz (1). `--check` eksik ve eski dosyayı ayırır. | Yol haritası M2, İlke 2 |
| D-30 | `risk` | `risk <spec> [--base <ref>]`; spec kimlikle (`001`) ya da klasörle verilir. Değişen yollar: `git merge-base <ref> HEAD`'den çalışma ağacına kadar `git diff --name-only` artı izlenmeyen dosyalar. Glob, `case` deseni olarak eşleşir (`*` `/`'yi de kapsar). Bir yol, uyduğu desenlerin en yükseğini, hiçbirine uymazsa `default`'u alır. Etkilenen bileşenler: spec'in `model` alanındakiler ve `paths`'i değişen bir yolu kapsayanlar; `risk`'i olmayan düğümler (ör. aktör) sayılmaz. Çıktı `spec`, `paths`, `components`, `risk` satırlarıdır. `risk` bir kapı değil bilgi verir; `verify`'da çalışmaz. | design §7 risk kademesi |
| D-31 | Stack denetimi ve `node` | M0'ın stack'e özel sözcük denetiminde yalın `node` sözcüğü, CALM'ın model öğesi adı olduğu için `node.js` ile değiştirildi; `nodejs`, `npm`, `npx` ve diğerleri yasak kalır. | AC-M0-09'un amacı (Node.js'e bağımlılık yok), CALM terimi |
| D-32 | `verify` ve `doctor` | `verify`'ın paket denetimleri `sync`, `model`, `views` (`--check`), `trace` sırasıyla çalışır. Model dosyası yoksa yapılandırma eksiği sayılır: hiçbir şey çalışmadan 2. `--fast` modeli istemez (D-06). `doctor` `risk.conf` sorunlarını ve modelin varlığını ayrı satırlarda raporlar. | İlke 4 ve 5, AC-M2-10 |
| D-33 | `status` | Spec başına `id durum risk başlık slices: <sayılar>`; sayılar `done, review, in-progress, planned` sırasıyla. Okunamayan alan `?` olarak gösterilir ve satıra `(run ./softwary trace)` eklenir. ADR'lerden yalnızca `proposed` olanlar listelenir. Her zaman 0 ile çıkar (kullanım hatası 2). | İlke 7 |

## M3

| No | Konu | Karar | Dayanak |
| --- | --- | --- | --- |
| D-34 | ADR üst bilgisi | Alanlar `id title status affects`; dördü de boş olamaz ve `UNSET` olamaz. Dosya adı `NNNN-ad.md`, `id` ilk dört hane. Durumlar `proposed accepted superseded rejected`. `affects` virgülle ayrılmış repo yollarıdır (bileşen kimliği değil): `architecture/` altında olmalı (`architecture/` + en az bir karakter; `..`, `.`, boş parça ve baştaki `/` yok) ve var olmalı. Dizin girdisi altındaki her yolu kapsar. `trace` bunları denetler ve ADR varsa ayrı bir `trace: N ADR(s)` satırı basar (M2 özet satırı değişmez). ADR şablonunun `affects` yorumu buna göre güncellendi. | AC-M3-03, İlke 4 |
| D-35 | `adr` kapısı | `adr [--base <ref>]` (varsayılan `main`): değişiklik kümesi, `git merge-base <ref> HEAD`'den çalışma ağacına kadar `git diff --no-renames --name-only` artı izlenmeyen dosyalardır; `--no-renames` sayesinde taşınan ya da silinen sözleşmenin eski yolu da görünür. Kapıya takılan yollar model dosyası ve `architecture/contracts/` altındaki her şeydir. Kapsayan ADR, değişiklik kümesinde bulunan (hâlâ var olan) `accepted` bir ADR'dir; `affects` girdisi yolu eşit ya da üst dizin olarak içermeli ve D-34 yol kuralına uymalıdır (yalın `architecture/` hiçbir şeyi kapsamaz). Yalnız `proposed` kapsıyorsa çıktı `awaiting human acceptance` der; ikisi de 1 verir. Taban (ya da ortak commit) yoksa ya da `-` ile başlıyorsa 2. `verify --base <ref>` `trace`'ten sonra `adr`'yi ekler; bayraksız `verify` `adr` çalıştırmaz (taban dalı olmayan depoda 2 verirdi), `--fast` ile `--base` birlikte kullanılamaz (2) ve geçersiz taban hiçbir kontrol çalışmadan 2 verir. | AC-M3-04, İlke 1 |
