# Yol haritası (v2)

v1 (M0–M4) tamamlandı: kapılar, yapıtlar, araç dağıtımı, kurulum ve aşama skill'leri. V1 (deneme düzeltmeleri) ve V2 (yürüyen iskelet) tamamlandı; V2'de tanım, blueprint, onaylar, plan, `job`/`run`/`merge` döngüsü ve `models.conf` var, kayıt D-65..D-82'dedir; durum kodu boyutu (D-81) insanın kararını bekliyor. V3 (güveni sertleştirme) tamamlandı: `guard` (korunan yollar, `touches`, test gevşetme), kapıda ve birleştirmede `guard`, bozuk diff'lerle değerlendirme (`eval prepare`/`score`) ve `min_catch_percent` eşiği var, kayıt D-83..D-96'dadır. V4 (paralel) tamamlandı: durum ana checkout'ta `mkdir` kilitleriyle yazılır, her iş kendi worktree'sinde ve `bootstrap`'lı yürür, `concurrency` (şablon 3) ve `touches` kesişmesiyle bölünmez kabul, çok satırlı `run next`, birleştirme kuyruğu (`queued`, `queue`, çöküşten devam) ve kırmızı entegrasyonda durma ile geri alma PR'ı var, birleştirme protokolü TLA+ ile belirtilip sekiz bozulmuş varyantla sınandı (`docs/formal/`), kayıt D-97..D-113'tedir; durum kodunun `sh`'te kalması insan kararıdır (D-81). v2 bunların üzerine tanım, blueprint, döngü ve paralel yürütmeyi kurar (`docs/design.md`). Buradaki her satır bir niyet ve verilmiş kararlardır; ayrıntılı spec sırası geldiğinde, önceki kilometre taşı birleştikten sonra yazılır. Gerçek kullanım denemesi bütün proje bitince yapılır.

| No | Kilometre taşı | Ne teslim eder | Verilmiş kararlar |
| --- | --- | --- | --- |
| V1 | Deneme düzeltmeleri | Entegrasyon ve üretim dalı ayarları, süreli muafiyetler, dürüst `doctor`, isteğe bağlı `CODEOWNERS`, skill'lerde `--fast`, boş repo yolu | Dal koruması insan incelemesi değil CI şart koşar |
| V2 | Yürüyen iskelet | Boş bir repoda uçtan uca: ince `define` ve `approve product`, ince blueprint (CALM, veri modeli) ve `approve blueprint`, `depends_on`'lu plan, sıralı döngü (`job`, `transitions.json`, olay günlüğü, kapı, PR ve CI, bir inceleyici, approver), bütçe ve tur sınırı, `models.conf` | Döngü `main`'e birleştirir; onaylar içerik özetidir; Opus planlar ve inceler, Sonnet uygular |
| V3 | Güveni sertleştirme | Korunan yollar, diff ⊆ `touches`, test gevşetme denetimleri, R3 escalate, bozuk diff'lerle değerlendirme | Birleştirme scripti kayıtlı PASS'e güvenmez |
| V4 | Paralel | Worktree'ler, `mkdir` kilitleri, birleştirme kuyruğu, çöküşten devam, birleştirme protokolünün TLA+ belirtimi | En fazla 3 eşzamanlı iş |
| V5 | Tanım ve blueprint'i derinleştirme | Sorgulama, akışlar, durum makineleri, blueprint eleştirmeni, `next`, `handoff`; durum makineleri ve kritik akışlar için TLA+ belirtimi, `model_check` kapısı (belirtim varsa zorunlu), değişmez cümlelerinin blueprint onayına girmesi, bozulmuş varyant kanıtı, ihlal yolunun ve durum diyagramının okurun diliyle gösterilmesi | Diyagramlar yapısal kaynaktan üretilir; biçimsel doğrulama ürüne uygulanır (D-63) |
| V6 | Mevcut repo | Taban çizgisi ve muafiyetlerle mevcut bir repoda döngü | Önce proje tamamlanır |
| V7 | Teslim ve işletim | `ship` (üretim dalına alma önerisi), `diagnose`, drift | Üretime dağıtım insan onayıyla |
| V8 | Biçimsel doğrulamayı derinleştirme | Belirtim ile kod arasındaki sapma bakımı (kapsam kaydı, son doğrulanan commit, uyumlu/güncellendi/hata/engelli), karşı örneklerin koda karşı test olarak yeniden oynatılması, belirtimden kabul testi türetme, R3 saf algoritmalar için isteğe bağlı Lean kanıtı | Kodun belirtime uyduğu iddia edilmez; boşluk testlerle daraltılır |
| V9 | Cursor ve sürüm | Cursor orkestratörü, kurulum kanalları, `uninstall`, İngilizce belgeler, `v0.1.0` | MIT, telemetri yok, anlamsal sürümleme |

## Sıra kuralları

- **Bir seferde bir kilometre taşı.** Bir sonrakinin spec'i, önceki birleşmeden yazılmaz.
- **Gerçek kullanım sonda.** Kilometre taşları arasında deneme yapılmaz; insan bütün proje bitince dener (D-64). Arada doğrulama, testler, `shellcheck` ve mutasyon denetimiyle yapılır.
- **Önce çalışan döngü.** Tanım ve blueprint, döngünün takıldığı yerlere göre derinleştirilir.
- **Sıra değişebilir.** V5'ten sonrasının sırası insan kararıyla yeniden belirlenebilir.

## Sonraki fikirler

Karar verilmedi, yalnızca not:

- Daha güçlü onay sınırı: imzalı onay ya da ajanlar için ayrı bir GitHub kimliği.
- İnceleme için farklı model ailesinden ikinci görüş.
- Issue tracker ile iki yönlü eşitleme.
