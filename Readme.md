# Ruby Orchestrator

## Mimari Özeti ve Özellikler

### Genel bakış

**Ruby Orchestrator**, farklı AI modellerini, MCP üzerinden erişilebilen harici araçları ve tekrar kullanılabilir iş akışlarını tek bir çalışma düzeninde bir araya getirmeyi amaçlayan otonom bir orkestratördür. Mimari yaklaşım dört ana ilkeye dayanır: **Cycle**, **Learn**, **Automate** ve **Connect**. Bu ilkeler sistemi sürekli çalıştırma, bağlamdan yararlanma, yinelenen işleri yürütme ve dış servislerle etkileşim kurma yönlerinde tanımlar.

### Temel döngü (Core Loop)

- **Cycle — sürekli çalışma:** İşleyişin tekrarlanabilir bir döngü içinde sürmesini sağlar. Döngü, işi başlatma ve sonraki adımlara geçme çerçevesini oluşturur. Tetikleyici ve zamanlama mekanizmasının ayrıntısı bu özette belirtilmemiştir.
- **Learn — bağlam ve geri bildirimlerden öğrenme:** Önceki bağlamı ve kullanıcı/iş akışı geri bildirimlerini sonraki çalışmalarda kullanmayı hedefler. Böylece her görevin tamamen sıfırdan ele alınması yerine, ilgili bilgi çalışma sürecine taşınabilir.
- **Automate — tekrarlayan işleri yürütme:** Tekrar eden görev adımlarını tanımlı iş akışları üzerinden otonom biçimde yürütür. Komut havuzu ve iş akışı şablonları bu ilkenin tekrar kullanılabilir parçalarını sağlar.
- **Connect — araç ve servislerle iletişim:** MCP sunucuları ve diğer harici servisler üzerinden orkestratörün erişebildiği yetenekleri genişletir. Araç kullanımı, görevin ihtiyaç duyduğu dış işlemlerin sisteme bağlanmasını sağlar.

Bu dört ilke birlikte ele alındığında, orkestratörün bağlamı değerlendirip uygun model ve araçları kullanarak bir iş akışını yürütmesi, ardından edinilen geri bildirimi sonraki döngüler için kullanması hedeflenir. Bu açıklama kavramsal akışı anlatır; uygulamadaki kesin sıralama veya kontrol mekanizması ayrıca doğrulanmalıdır.

### Mimari bileşenler

#### Model Bridge — çoklu model orkestrasyonu

Model Bridge, farklı AI modellerine erişimi tek bir adaptör katmanında toplar. Kapsamına LLM'ler, yerel modeller ve özel API'ler girer. Bu katmanın mimarideki temel rolü, üstteki iş akışlarının her modelin farklı bağlantı biçimlerine doğrudan bağımlı kalmasını önlemek ve model erişimini ortak bir arayüz üzerinden düzenlemektir.

Özet, model seçiminin hangi ölçütlerle yapıldığını (ör. görev türü, maliyet, hız veya yerel çalıştırma gereksinimi) belirtmiyor; bunlar uygulama ayrıntısı olarak ayrıca kararlaştırılabilir.

#### MCP entegrasyonu — harici yeteneklere erişim

MCP (Model Context Protocol) entegrasyonu, harici MCP sunucularına ve sundukları araçlara dinamik olarak bağlanmayı sağlar. Kullanıcı tarafından belirtilen arayüz akışı şöyledir:

1. `Routers` bölümüne gir.
2. `Servers` sekmesini aç.
3. İlgili `MCP` sunucusunu seç.
4. İstenen komut veya aksiyonu tetikle.

Bu entegrasyon, orkestratörün yalnızca model yanıtı üretmekle sınırlı kalmayıp uygun harici araçlarla işlem yapabilmesini destekler. Hangi sunucuların kullanılabileceği ve hangi aksiyonların yetkilendirileceği bağlantı/izin ayarlarına bağlıdır; burada belirli bir sunucu listesi tanımlanmamıştır.

#### State & Shared Memory — ortak bellek ve durum yönetimi

Ortak bellek ve merkezi durum yönetimi, modeller ve MCP sunucuları arasında bağlamın korunmasını hedefler. Böylece bir bileşenin ürettiği veya kullandığı ilgili durumun diğer bileşenlerin çalışmasına aktarılması mümkün olur. Bu katman, özellikle çok adımlı işlerde bağlamın kopmasını azaltan ortak koordinasyon noktasıdır.

Belleğin kalıcılık süresi, hangi verilerin saklanacağı, erişim sınırları ve güncelleme/temizleme kuralları bu özette tanımlanmamıştır; bunlar güvenilir bir uygulama tasarımı için ayrıca netleştirilmelidir.

#### Command Pool & Workflows — komut havuzu ve iş akışları

Komut havuzu, tekrar kullanılabilen komut veya görev adımlarını; iş akışı şablonları ise bu adımların belirli proje ve kurulum süreçlerinde nasıl bir araya geleceğini temsil eder. Bu yapı, benzer işlerin her seferinde baştan tarif edilmesi ihtiyacını azaltmayı ve yürütme biçimini standartlaştırmayı amaçlar.

Şablonların nasıl oluşturulduğu, sürümlendiği, parametre aldığı veya onay gerektirdiği belirtilmemiştir. Bunlar mevcut özellik olarak değil, ileride dokümante edilebilecek tasarım ayrıntıları olarak değerlendirilmelidir.

### Kavramsal uçtan uca çalışma akışı

1. **İş ve bağlam belirlenir:** Döngü, yürütülecek görevi ve ilgili mevcut durumu ele alır.
2. **Uygun model ve araçlar kullanılır:** Model Bridge model erişimini, MCP bağlantıları ise gerekli harici yetenekleri sağlar.
3. **İş akışı yürütülür:** Tekrar eden veya önceden tanımlı adımlar, komut havuzu ve iş akışı şablonlarıyla çalıştırılır.
4. **Durum paylaşılır:** İlgili bağlam, bileşenler arasında merkezi durum/bellek yaklaşımıyla korunur.
5. **Geri bildirim sonraki döngüye taşınır:** Öğrenme ilkesi, elde edilen bağlam ve geri bildirimin sonraki çalışmalarda kullanılmasını hedefler.

Bu sıra, mevcut özelliklerin birbirleriyle ilişkisini açıklayan bir modeldir; ürünün kesin çalışma sırası olarak doğrulanmış değildir.

### İlk kod iskeleti

İlk uygulama iskeleti aşağıdaki sorumluluklara göre ayrılmıştır:

```text
bin/                         CLI giriş noktası
config/                      Uygulama, model, MCP ve zamanlama ayarları
workflows/                   YAML iş akışları
db/migrations/               SQLite şema değişiklikleri
memory/notes/                Markdown tabanlı uzun süreli notlar
lib/ruby_orchestrator/
  run.rb                     Bir çalıştırmanın durumu ve yaşam döngüsü
  orchestrator.rb            Workflow çalıştırıcısını çağıran koordinatör
  cli/ api/ scheduler/       Arayüz ve tetikleme katmanları
  mcp/ policies/ memory/     Araç, izin ve bellek katmanları
  observability/             Çalışma kayıtları ve olaylar
spec/                        Birim ve entegrasyon testleri
```

`RubyOrchestrator::Run`, bir çalıştırmanın `pending → running → succeeded/failed` durum geçişlerini ve zaman damgalarını tutar. `RubyOrchestrator::Orchestrator`, enjekte edilen bir workflow çalıştırıcısını çağırır; başarılı sonucu `Run` üzerinde döndürür ve çalıştırıcı hata verirse hatayı sessizce yutmak yerine tekrar yükseltir. `RubyOrchestrator::Memory::SQLiteStore`, `Run` kayıtlarını SQLite'a yazar ve kimliğe göre JSON uyumlu bir kayıt olarak geri okur. Örnek kullanım:

```ruby
require "ruby_orchestrator"

runner = ->(run) { "Workflow: #{run.workflow}" }
orchestrator = RubyOrchestrator::Orchestrator.new(workflow_runner: runner)
run = orchestrator.execute(workflow: "sample", input: { "name" => "Ruby" })
store = RubyOrchestrator::Memory::SQLiteStore.new(path: "db/ruby_orchestrator.sqlite3")
store.save(run)
record = store.find(run.id)
store.close
```

Bu adımda YAML yükleme, gerçek workflow yürütme, Markdown kalıcılığı, API/CLI ve MCP bağlantısı henüz uygulanmamıştır; bunlar ilgili katmanlar eklendikçe bağlanacaktır. SQLite depolaması için `sqlite3` gem'i gerekir.

### Netleştirilebilecek mimari kararlar

Aşağıdaki başlıklar mevcut özetin doğruladığı özellikler değil, mimariyi uygulama ve işletim açısından daha belirgin hale getirmek için açık bırakılmış konulardır:

- Görevlerin döngüyü hangi olay veya zamanlama ile başlattığı.
- Model Bridge'in model seçimini hangi kurallarla yaptığı ve başarısızlık durumunda nasıl davrandığı.
- MCP araçları için izin, onay ve hata/yeniden deneme yaklaşımı.
- Ortak bellekte hangi verilerin ne kadar süre saklandığı ve kimlerin erişebildiği.
- İş akışlarının nasıl tanımlandığı, sürümlendiği ve hangi koşullarda çalıştırıldığı.
- Çalışma adımlarının nasıl izlendiği, kaydedildiği ve gerektiğinde denetlendiği.