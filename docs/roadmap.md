# Yol haritası (v2)

v1 (M0–M4) tamamlandı: kapılar, yapıtlar, araç dağıtımı, kurulum ve aşama skill'leri. v2 bunların üzerine tanım, blueprint, döngü ve paralel yürütmeyi kurar (`docs/design.md`). Buradaki her satır bir niyet ve verilmiş kararlardır; ayrıntılı spec sırası geldiğinde, önceki kilometre taşının gerçek kullanım denemesinden öğrenilenlerle yazılır.

| No | Kilometre taşı | Ne teslim eder | Verilmiş kararlar |
| --- | --- | --- | --- |
| V1 | Deneme düzeltmeleri | Entegrasyon ve üretim dalı ayarları, süreli muafiyetler, dürüst `doctor`, isteğe bağlı `CODEOWNERS`, skill'lerde `--fast`, boş repo yolu | Dal koruması insan incelemesi değil CI şart koşar |
| V2 | Yürüyen iskelet | Boş bir repoda uçtan uca: ince `define` ve `approve product`, ince blueprint (CALM, veri modeli) ve `approve blueprint`, `depends_on`'lu plan, sıralı döngü (`job`, `transitions.json`, olay günlüğü, kapı, PR ve CI, bir inceleyici, approver), bütçe ve tur sınırı, `models.conf` | Döngü `main`'e birleştirir; onaylar içerik özetidir; Opus planlar ve inceler, Sonnet uygular |
| V3 | Güveni sertleştirme | Korunan yollar, diff ⊆ `touches`, test gevşetme denetimleri, R3 escalate, bozuk diff'lerle değerlendirme | Birleştirme scripti kayıtlı PASS'e güvenmez |
| V4 | Paralel | Worktree'ler, `mkdir` kilitleri, birleştirme kuyruğu, çöküşten devam, birleştirme protokolünün TLA+ belirtimi | En fazla 3 eşzamanlı iş |
| V5 | Tanım ve blueprint'i derinleştirme | Sorgulama, akışlar, durum makineleri, blueprint eleştirmeni, `next`, `handoff` | Diyagramlar yapısal kaynaktan üretilir |
| V6 | Mevcut repo | Taban çizgisi ve muafiyetlerle mevcut bir repoda döngü | Önce proje tamamlanır |
| V7 | Teslim ve işletim | `ship` (üretim dalına alma önerisi), `diagnose`, drift | Üretime dağıtım insan onayıyla |
| V8 | Proje biçimsel doğrulaması | `model_check` kapısı, blueprint'te biçimsel belirtim | Kodun belirtime uyduğu iddia edilmez |
| V9 | Cursor ve sürüm | Cursor orkestratörü, kurulum kanalları, `uninstall`, İngilizce belgeler, `v0.1.0` | MIT, telemetri yok, anlamsal sürümleme |

## Sıra kuralları

- **Bir seferde bir kilometre taşı.** Bir sonrakinin spec'i, önceki bitmeden ve denenmeden yazılmaz.
- **Her kilometre taşından sonra gerçek kullanım.** Deneme notları bir sonraki spec'in girdisidir.
- **Önce çalışan döngü.** Tanım ve blueprint, döngünün takıldığı yerlere göre derinleştirilir.
- **Sıra değişebilir.** V5'ten sonrasının sırası, kullanımda en çok eksikliği hissedilene göre yeniden belirlenir.

## Sonraki fikirler

Karar verilmedi, yalnızca not:

- Daha güçlü onay sınırı: imzalı onay ya da ajanlar için ayrı bir GitHub kimliği.
- İnceleme için farklı model ailesinden ikinci görüş.
- Issue tracker ile iki yönlü eşitleme.
