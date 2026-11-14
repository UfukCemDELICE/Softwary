# softwary — Çekirdek tasarım

Nov 14, 2026 · @Ufuk Cem Delice

softwary, kurulduğu repoyu bütün SDLC'yi ajanlarla yürüten ama kalite sorumluluğunu mühendiste tutan bir yazılım fabrikasına çeviren, araçtan ve stack'ten bağımsız, MIT lisanslı açık kaynak bir pakettir. Bu belge her oturumda okunan tek kalıcı tasarımdır. Kilometre taşlarının ayrıntısı kendi spec'lerinde, sonraki işler yol haritasındadır. Çelişki olursa bu belge geçerlidir.

## 1. Amaç

Kodu ajanlar yazar; mimariye, spec'e ve kaliteye mühendis hâkim kalır. Paketi hazır skill paketlerinden ayıran üç şey vardır ve emek önce bunlara gider:

- Mimari model tek doğruluk kaynağıdır.
- Kapılar script ve CI ile uygulanır, ajanın iyi niyetine bırakılmaz.
- Model ile kod arasındaki sapma izlenir.

Hedef dışı: ürün ya da arayüz, kendi ajan çalışma zamanı, stack adaptörü ya da proje şablonu, ekip ve issue tracker entegrasyonu, regülasyon uyumu.

## 2. İlkeler

Karara bağlanmamış her durumda yapıcı bu sekiz ilkeye göre karar verir.

1. **Talimat değil kapı.** Kritik her kural bir script kontrolüyle uygulanır.
2. **Tek kaynak, üretilen kopyalar.** Araca özel dosyalar `sync` ile üretilir, elle düzenlenmez.
3. **Sözleşme pakette, karşılığı projede.** Paket komut isimlerini tanımlar, gerçek komutlar projenin yapılandırmasında durur.
4. **Yapılandırılmamış olan başarısızdır.** Hiçbir kontrol sessizce geçmez ya da atlanmaz.
5. **Model önce.** Mimari değişiklik önce modelde yapılır ve insan onayı alır.
6. **Yazan incelemez.** İnceleme temiz bağlamlı ayrı bir ajanla yapılır.
7. **Kısa ve yapısal yapıtlar.** Beş dakikada okunamayan yapıt yanlış biçimdedir.
8. **Aşamalı bağlam.** Her oturumda yüklenen dosya kısadır, ayrıntı skill çağrılınca gelir.

## 3. Paket mimarisi

Kurulum dosya kopyalamaktır. Scriptler POSIX `sh` ile yazılır; ek bağımlılıklar `git` ve `jq`. Paket içeriği ve belgeler İngilizcedir.

```
<repo>/
  softwary              sarmalayıcı, .softwary/bin/softwary'yi çağırır
  AGENTS.md  CLAUDE.md  üretilir (yönetilen blok)
  CONTEXT.md            alan sözlüğü
  .softwary/
    bin/ lib/ rules/ skills/ agents/ templates/ targets/   yönetilen
    config/             commands.conf, risk.conf, tools.conf
    local/              projeye özel ekler
    state/              kayıtlar, git'e eklenmez
  architecture/         model/ contracts/ views/ decisions/
  specs/<no>-<ad>/      spec.md, slices/, reviews/
  .claude/ .cursor/ .agents/ .codex/    üretilir
```

- **Yönetilen** dosyalar güncellemede üzerine yazılır. **Projeye ait** dosyalara (`config/`, `local/`, `architecture/`, `specs/`, `CONTEXT.md`) paket dokunmaz. **Üretilen** dosyalar commit'lenir ve güncellikleri CI'da denetlenir.
- Mevcut `AGENTS.md` korunur; paket yalnızca kendi işaretçileri arasını yazar.
- Aynı adlı `local/` dosyası yönetileni ezer.

## 4. Komut sözleşmesi

Skill'ler, hook'lar ve CI yalnızca sözleşme isimlerini kullanır. Gerçek komutlar `.softwary/config/commands.conf` dosyasında `anahtar = değer` biçiminde durur.

| Anahtar | Garanti | Durum |
| --- | --- | --- |
| `format_check`, `lint`, `typecheck` | Biçim, statik analiz ve tip denetimi temiz | Zorunlu |
| `test`, `build` | Testler geçiyor, çıktı üretiliyor | Zorunlu |
| `security` | Bağımlılık açığı ve gizli bilgi taraması temiz | Zorunlu |
| `contract_check` | Uygulama sözleşme dosyalarıyla uyumlu | Sözleşme varsa zorunlu |
| `arch_check` | Modeldeki bağımlılık kurallarına uyuluyor | Birden fazla bileşen varsa zorunlu |
| `run`, `deploy`, `bootstrap` | Yerelde başlatma, dağıtım, yeni kopyayı hazırlama | İsteğe bağlı |

Bir değer üç biçimden biridir: bir komut (çıkış kodu 0 ise geçer), `UNSET` (zorunlu anahtarda hata) ya da `NONE: <gerekçe>` (atlanır, gerekçe raporda görünür). `test_paths` ve `src_paths` komut değil ayardır.

Paketin kendi komutları: `verify`, `verify --fast`, `trace`, `model validate`, `views`, `drift`, `risk`, `status`, `sync`, `doctor`, `upgrade`. Her biri ilgili kilometre taşında eklenir.

`verify` ucuzdan pahalıya çalışır ve ilk hatada durmaz: paketin kendi denetimleri, biçim ve statik denetimler, test ve derleme, sözleşme ve mimari ve güvenlik. Çıktı ajanın okuması içindir:

- Kontrol başına tek satır: `PASS`, `FAIL` ya da `SKIP (gerekçe)`.
- Hatada çıktının yalnızca son satırları basılır, tam kayıt `.softwary/state/logs/` altına yazılır.
- Çıkış kodları: `0` geçti, `1` başarısız, `2` yapılandırma eksik.

## 5. Yapıtlar

Fabrikanın durumu repodaki dosyalarda tutulur. Üst bilgi alanları düz `anahtar: değer` satırlarıdır.

| Yapıt | Yol | Alanlar | Onay |
| --- | --- | --- | --- |
| Mimari model | `architecture/model/system.calm.json` | Bileşenler, ilişkiler, arayüzler; bileşen başına `paths`, `risk`, `status` | İnsan, ADR ile |
| Sözleşmeler | `architecture/contracts/` | OpenAPI, AsyncAPI | İnsan, ADR ile |
| Görünümler | `architecture/views/*.mmd` | Modelden üretilir | Yok |
| Karar (ADR) | `architecture/decisions/NNNN-ad.md` | `id`, `title`, `status`, `affects`; seçenekler tablosu | İnsan |
| Sözlük | `CONTEXT.md` | Terim, tanım, kaçınılacak eş anlamlılar | İnsan |
| Spec | `specs/NNN-ad/spec.md` | `id`, `title`, `status`, `risk`, `model`, `contracts`; kabul kriterleri `AC-<spec>-<sıra>` | İnsan |
| Dilim | `specs/NNN-ad/slices/Sx.md` | `id`, `spec`, `goal`, `acs`, `depends_on`, `touches`, `status`; notlar | Yok |
| İnceleme | `specs/NNN-ad/reviews/Sx.md` | Özet, bulgular, okunacak dosyalar, karar | Yok |

- Bir spec bir sayfayı geçmez ve açık sorusu varken onaylanamaz.
- Bir dilim uçtan uca gözlenebilir tek bir davranışı teslim eder ve tek oturumda biter.
- İzlenebilirlik: her kabul kriteri tam olarak bir dilime aittir; `review` ya da `done` durumundaki bir dilimin her kriter kimliği `test_paths` altındaki en az bir dosyada geçer.
- Modeli ya da sözleşmeleri değiştiren her değişiklik bir ADR içerir.

Durum geçişlerinde ajanlar bir yapıtı `approved` ya da `accepted` yapamaz.

## 6. Hat

| Aşama | Skill | Çıktı | Kapı |
| --- | --- | --- | --- |
| Kurulum | `setup` | Yapılandırma, hook'lar, CI | `doctor` geçer |
| Keşif | `discover` | Hikâyeler, sözlük, açık sorular | İnsan yanıtladı |
| Mimari | `architect` | Model, sözleşmeler, ADR | İnsan ADR'yi kabul etti |
| Spec | `specify` | `spec.md` | İnsan onayladı |
| Dilimleme | `slice` | Dilimler | `trace` geçer |
| Uygulama | `implement` | Testler, kod, notlar | `verify` geçer |
| İnceleme | `review` | İnceleme kaydı | İnceleme ve riske göre insan onayı |
| Teslim | `ship` | PR, sürüm notu | CI yeşil, insan onayı |
| İşletim | `diagnose` | Yeniden üreten test, düzeltme | `verify` geçer |
| Bakım | `maintain` | Drift raporu, güncellemeler | İnsan drift kararını verdi |

Yardımcı skill'ler: `next` (sıradaki adım) ve `handoff` (oturum sonu notları). Subagent'lar: `spec-analyst`, `implementer`, `reviewer`, `drift-auditor`. Kurulan skill adları `softwary-` öneki taşır.

`implement` önce kabul kriteri kimliğini taşıyan testi yazar, sonra kodu, sonra `verify`'ı geçirir. Üç yasağı vardır: testi zayıflatmak, `.softwary/config/` dosyalarını değiştirmek, modeli ya da sözleşmeyi sessizce değiştirmek. Aynı hata üç denemede çözülmezse durur.

## 7. İnsan denetimi

İnsan beş kararı verir ve bunlar devredilemez: mimari karar, spec onayı, birleştirme onayı, drift kararı, üretime dağıtım.

Kesin kurallar her oturumda yüklenir:

1. Onaylanmış spec ve dilim olmadan kod yazılmaz.
2. `./softwary verify` çıktısı gösterilmeden iş bitmiş ilan edilmez.
3. Testler, kapılar ve yapılandırma zayıflatılmaz.
4. Model ve sözleşmeler yalnızca `architect` aşamasında değişir.
5. Üretilen dosyalar elle düzenlenmez.
6. Belirsizlikte varsayım yapılmaz, soru sorulur.
7. Gizli bilgi içeren dosyalar okunmaz ve commit'lenmez.

Risk kademesi insanın ne kadar inceleyeceğini belirler: R1 düşük (özete göz atılır), R2 normal (özet ve işaretli dosyalar okunur), R3 kritik (satır satır okunur, otomatik birleştirme yok). Geçerli kademe spec'in, değişen yolların (`risk.conf`) ve etkilenen bileşenin en yükseğidir.

Kapılar üç noktada çalışır: ajan döngüsünde ve git hook'larında hızlı geri besleme için, CI'da zorunlu olarak. Onaylar uzak repoda dal koruması ve `CODEOWNERS` ile korunur.

## 8. Araç dağıtımı

Kaynak bir kez yazılır, `sync` her araç için bir hedef scriptiyle çevirir. Yeni araç eklemek tek bir hedef scripti eklemektir.

| Kaynak | Claude Code | Cursor | Codex |
| --- | --- | --- | --- |
| Kuralların girişi | `CLAUDE.md` | `AGENTS.md` | `AGENTS.md` |
| Skill'ler | `.claude/skills/` | `.cursor/skills/` | `.agents/skills/` |
| Subagent'lar | `.claude/agents/*.md` | `.cursor/agents/*.md` | `.codex/agents/*.toml` |

Skill üst bilgisi yalnızca `name` ve `description` taşır. Subagent'ı desteklemeyen araçta rol skill olarak üretilir ve temiz bir oturumda çalıştırılır.

## 9. Kararlar ve varsayımlar

Verilmiş kararlar:

- Paket adı `softwary`, repo herkese açık, lisans MIT.
- Araçtan ve stack'ten bağımsız; pakette stack adaptörü yok.
- Model güdümlü yaklaşım ile spec güdümlü geliştirme birlikte.
- POSIX `sh`, `git`, `jq`; düz `anahtar = değer` yapılandırma.
- Üretilen dosyalar commit'lenir.
- Her değişikliğin, küçük de olsa, bir spec'i vardır.
- CI şablonu GitHub Actions içindir.

Araç yolları, subagent biçimleri ve `CLAUDE.md`'nin `AGENTS.md`'yi `@AGENTS.md` ile içe aktarabilmesi M1 öncesinde doğrulandı (`docs/decisions.md`). Yapıcının ilgili kilometre taşından önce güncel belgelerden doğrulayacağı varsayımlar:

| Varsayım | Yanlışsa |
| --- | --- |
| CALM metadata'sı `paths`, `risk`, `status` alanlarına izin verir | Yan dosyaya taşınır |
| Git hook yolu repodaki bir klasöre yönlendirilebilir | Hook'lar kopyalanır |

## 10. Yapım biçimi

- Her kilometre taşı ayrı bir oturumda, kendi spec'iyle yapılır. Spec, sırası geldiğinde ve öncekinden öğrenilenlerle yazılır.
- Yapıcı önce plan sunar, onaydan sonra testi önce yazarak uygular ve kabul kriterlerini çıktıyla gösterir.
- Belgede olmayan kararlar ilkelere göre verilir ve `docs/decisions.md` dosyasına yazılır.
- Bir karar değişirse önce bu belge değişir, sonra kod.
- Paket, hattı kurulduğu andan itibaren kendi üzerinde kullanılır.
