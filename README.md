# 🛡️ VitalGuard
### LSTM Tabanlı Akıllı Sağlık ve Kaza Takip Sistemi — On-Device AI

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.5-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Python-3.11-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/TensorFlow-2.x-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white" alt="TensorFlow">
  <img src="https://img.shields.io/badge/TFLite-On--Device%20AI-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white" alt="TensorFlow Lite">
</p>

<p align="center">
  <strong>Gerçek zamanlı aktivite tanıma, düşme tespiti ve kardiyak aritmi analizi yapan, yapay zekayı doğrudan mobil cihaz üzerinde çalıştıran akıllı sağlık ve güvenlik sistemi.</strong>
</p>

---

## 📌 Proje Hakkında

**VitalGuard**, akıllı telefon sensörleri ve giyilebilir cihazlardan alınan verileri kullanarak kullanıcının fiziksel aktivitelerini, olası düşme durumlarını ve kardiyak ritim anormalliklerini gerçek zamanlı olarak analiz eden bir mobil sağlık ve güvenlik sistemidir.

Projenin temel amacı, yapay zeka modellerini bulut sunucusuna göndermek yerine **doğrudan mobil cihaz üzerinde çalıştırarak (On-Device AI)** hızlı, düşük gecikmeli ve internet bağlantısına bağımlı olmayan bir sağlık takip altyapısı oluşturmaktır.

Sistem iki temel yapay zeka modülünü bir araya getirir:

- 🏃 **mHealth tabanlı aktivite tanıma ve düşme analizi**
- ❤️ **PTB Diagnostic ECG Database tabanlı kardiyak aritmi analizi**

Tespit edilen kritik durumlarda sistem, yanlış alarmları azaltmak amacıyla ek doğrulama mekanizmaları uygular ve durum doğrulandığında kullanıcının belirlediği acil durum kişilerine **GPS konumu ve otomatik SMS** gönderir.

---

## 🎯 Projenin Amaçları

- Gerçek zamanlı insan aktivitesi tanıma
- Düşme durumlarını otomatik olarak tespit etme
- Kardiyak ritim anomalilerini yapay zeka ile sınıflandırma
- Yapay zeka modellerini mobil cihaz üzerinde çalıştırma
- İnternet bağlantısı olmadan gerçek zamanlı analiz gerçekleştirme
- Yanlış pozitif alarm oranını azaltma
- Acil durumlarda otomatik konum paylaşımı
- Giyilebilir cihazlar ile BLE üzerinden haberleşme
- Enerji tüketimini azaltarak sürekli izleme sağlayabilme
- Kullanıcı güvenliğini proaktif bir şekilde artırma

---

# 🚀 Temel Özellikler

## 🧠 On-Device Artificial Intelligence

Model çıkarımları TensorFlow Lite kullanılarak doğrudan Android cihaz üzerinde gerçekleştirilir.

Bu sayede:

- Ağ bağlantısı gerektirmez
- Sunucu gecikmesi ortadan kaldırılır
- Ham sensör verilerinin dışarı gönderilmesine gerek kalmaz
- Gerçek zamanlı analiz yapılabilir
- Kullanıcı verilerinin gizliliği artırılır

---

## 🏃 İnsan Aktivitesi Tanıma

Sistem, akıllı telefonun:

- Accelerometer
- Gyroscope

sensörlerinden alınan hareket verilerini kullanarak insan aktivitelerini sınıflandırır.

mHealth veri seti üzerinde eğitilen iki katmanlı LSTM modeli:

- 12 farklı aktivite sınıfı
- 100 zaman adımı
- 12 özellikli giriş
- `(1, 100, 12)` TensorFlow Lite giriş boyutu

kullanır.

---

## 🛑 Akıllı Düşme Tespiti

Düşme algılama sistemi yalnızca tek bir ivme değerine bağlı değildir.

Yanlış pozitifleri azaltmak amacıyla çok aşamalı bir durum makinesi kullanılır.

### Düşme Algılama Akışı

~~~text
Hareket Verisi
      │
      ▼
┌─────────────────────────┐
│ Aktivite / Hareket      │
│ Analizi                 │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Yüksek İvmelenme        │
│ / Impact Detection      │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ 1.5 sn Recovery Check   │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ 1.5 - 10 sn             │
│ Inactivity Check        │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ 12 sn Kullanıcı         │
│ Onay Süresi             │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  ACİL DURUM PROTOKOLÜ   │
└─────────────────────────┘

~~~

### Kullanılan filtreler

Sistem;

- Koşma
- Bisiklete binme
- Zıplama
- Yüksek hareketli aktiviteler
- Ani ivmelenmeler

gibi normal aktivitelerin yanlışlıkla düşme olarak değerlendirilmesini azaltmak için ek kontroller gerçekleştirir.

Düşme algılama durum makinesinin temel aşamaları:

1. Yüksek eforlu aktiviteler için yanlış pozitif filtreleme
2. Impact detection
3. İlk 1.5 saniyelik recovery kontrolü
4. 1.5–10 saniye hareketsizlik kontrolü
5. Alarm sonrasında 60 saniyelik cooldown

Impact algılama sırasında ivme büyüklüğü için **25g üzeri** eşik kullanılmaktadır.

Recovery aşamasında hareket varyansı `0.10` değerinin altında olduğunda hızlı stabilizasyon değerlendirilir.

---

# ❤️ Kardiyak Aritmi Tespiti

Sistem, **PTB Diagnostic ECG Database** kullanılarak geliştirilen Conv1D + LSTM hibrit modeli ile ECG sinyallerini analiz eder.

Model:

~~~text
ECG Input
(187, 1)
     │
     ▼
Conv1D
32 Filters
Kernel Size: 3
     │
     ▼
ReLU
     │
     ▼
MaxPooling1D
Pool Size: 2
     │
     ▼
LSTM
64 Units
     │
     ▼
Dropout
0.2
     │
     ▼
LSTM
64 Units
     │
     ▼
Dropout
0.2
     │
     ▼
Dense
1 Unit
     │
     ▼
Sigmoid
     │
     ▼
Kardiyak Sınıflandırma
~~~

Model;

- Adam optimizer
- Learning rate: `0.001`
- Binary Crossentropy
- Batch size: `64`
- EarlyStopping
- %80 eğitim / %20 test

ayarlarıyla geliştirilmiştir.

TensorFlow Lite giriş boyutu:

~~~text
(1, 187, 1)
~~~

---

# 📊 Model Performansı

## 🏃 mHealth Aktivite Tanıma

| Model | Accuracy | Sensitivity | Specificity | F1-Score |
|---|---:|---:|---:|---:|
| k-NN | 87.2% | 81.4% | 81.3% | 82.6% |
| SVM | 90.1% | 85.7% | 85.7% | 86.3% |
| **2-Layer LSTM** | **98.4%** | **97.9%** | **97.8%** | **98.1%** |

LSTM modeli, geleneksel k-NN ve SVM yöntemlerine kıyasla daha yüksek sınıflandırma performansı göstermiştir.

---

## ❤️ PTB-DB Kardiyak Analizi

| Model | Accuracy | Sensitivity | Specificity | F1-Score |
|---|---:|---:|---:|---:|
| k-NN | 86.5% | 83.2% | 83.1% | 84.0% |
| **Conv1D + LSTM** | **97.8%** | **96.5%** | **98.2%** | **97.3%** |

Conv1D katmanı ECG sinyalindeki yerel özellikleri çıkarırken LSTM katmanları zamansal ilişkilerin öğrenilmesini sağlar.

---

# ⚡ TensorFlow Lite Optimizasyonu

Modeller mobil cihazlarda çalıştırılabilmek için TensorFlow Lite formatına dönüştürülmüştür.

| Model | Keras Boyutu | TFLite Boyutu | Ortalama Inference |
|---|---:|---:|---:|
| mHealth LSTM | ~679 KB | ~227 KB | 8–15 ms |
| ECG Conv1D + LSTM | ~741 KB | ~90 KB | 5–10 ms |

TensorFlow Lite dönüşümü sonucunda model boyutlarında önemli ölçüde azalma sağlanmıştır.

Özellikle ECG modeli:

~~~text
~741 KB
   ↓
~90 KB
~~~

seviyesine düşürülmüştür.

Bu optimizasyon, modellerin mobil cihaz üzerinde düşük gecikmeyle çalıştırılmasını mümkün hale getirir.

---

# 📱 Mobil Uygulama Mimarisi

Uygulama Flutter kullanılarak geliştirilmiş ve servis tabanlı bir mimariye ayrılmıştır.

~~~text
┌───────────────────────────────────────┐
│             PRESENTATION              │
│        Screens / Widgets / UI         │
└───────────────────┬───────────────────┘
                    │
                    ▼
┌───────────────────────────────────────┐
│          STATE MANAGEMENT             │
│ MonitoringController / Provider       │
│ ChangeNotifier Singleton              │
└───────────────────┬───────────────────┘
                    │
                    ▼
┌───────────────────────────────────────┐
│              SERVICES                 │
│                                       │
│  SensorService                        │
│  AIService                            │
│  BLEService                           │
│  EmergencyService                     │
└───────────────────┬───────────────────┘
                    │
                    ▼
┌───────────────────────────────────────┐
│           DATA / MODELS               │
│                                       │
│ SensorData                            │
│ UserProfile                           │
│ AnomalyEvent                          │
└───────────────────────────────────────┘
~~~

---

# 🔌 Sensör Sistemi

Mobil cihazdaki sensörlerden gerçek zamanlı veri alınır.

Kullanılan temel sensörler:

- Accelerometer
- Gyroscope
- Significant Motion Sensor

Sensör verileri yaklaşık **50 ms periyotla** işlenmektedir.

Significant Motion Sensor sayesinde cihaz sürekli olarak ağır AI işlemleri yapmak zorunda kalmaz.

Bu yaklaşım:

- CPU kullanımını azaltır
- Gereksiz inference işlemlerini önler
- Batarya tüketimini azaltır
- Arka planda sürekli izlemeyi daha verimli hale getirir

---

# ⌚ Akıllı Saat / BLE Entegrasyonu

Sistem, Bluetooth Low Energy üzerinden uyumlu giyilebilir cihazlarla iletişim kurabilir.

BLE bağlantısı için:

~~~text
flutter_blue_plus
~~~

paketi kullanılmaktadır.

Acil durum algılandığında bağlantılı akıllı saate alarm sinyali gönderilebilir ve cihaz üzerinde titreşim geri bildirimi oluşturulabilir.

---

# 🚨 Acil Durum Protokolü

Sistem kritik bir durum tespit ettiğinde doğrudan SMS göndermek yerine kullanıcıya **12 saniyelik doğrulama süresi** tanır.

~~~text
AI / Sensor Detection
          │
          ▼
   Critical Situation
          │
          ▼
   12 Second Countdown
          │
      ┌───┴───┐
      │       │
   Cancel   No Response
      │       │
      ▼       ▼
    STOP   GPS Location
              │
              ▼
       Google Maps Link
              │
              ▼
       Automatic SMS
              │
              ▼
      Emergency Contact
~~~

Acil durum doğrulandığında:

1. GPS konumu alınır.
2. Google Maps konum bağlantısı oluşturulur.
3. Kullanıcının acil durum kişisine SMS gönderilir.
4. BLE üzerinden bağlı giyilebilir cihaza alarm gönderilebilir.

Testlerde GPS konumunun alınması ortalama **2–3 saniye** sürmüştür.

---

# 🔋 Enerji Verimliliği

Uygulama sürekli sensör takibi gerçekleştirdiği için enerji tüketimi önemli bir tasarım kriteridir.

Bu nedenle:

### Significant Motion Sensor

Kullanıcının önemli bir hareket gerçekleştirmediği durumlarda ağır analiz işlemlerinin gereksiz yere çalıştırılması azaltılır.

### TensorFlow Lite

Küçük ve optimize edilmiş modeller sayesinde mobil cihaz üzerinde düşük gecikmeli inference gerçekleştirilir.

### Foreground Service

Android 14+ cihazlarda arka planda izleme işleminin devam edebilmesi için foreground service yaklaşımı kullanılmaktadır.

Kullanılan paket:

~~~text
flutter_foreground_task
~~~

---

# 🏗️ Proje Yapısı

~~~text
LSTM-Tabanli-Mobil-Saglik-Sistemi-ile-Aktivite-Dusme-ve-Kardiyak-Aritmi-Tespiti/
│
├── bitirme_mobil/
│   │
│   ├── android/
│   ├── ios/
│   ├── lib/
│   │   ├── screens/
│   │   ├── widgets/
│   │   ├── services/
│   │   ├── models/
│   │   ├── controllers/
│   │   └── utils/
│   │
│   ├── assets/
│   │   └── models/
│   │       ├── mhealth_lstm.tflite
│   │       └── ecg_model.tflite
│   │
│   ├── pubspec.yaml
│   └── ...
│
├── model_training/
│   ├── mhealth/
│   ├── ecg/
│   └── ...
│
└── README.md
~~~

> Proje klasörlerinin gerçek repository yapısına göre güncellenmesi gerekebilir.

---

# 🧰 Kullanılan Teknolojiler

## Mobile

- Flutter 3.x
- Dart 3.5
- Android
- Flutter Provider / ChangeNotifier

## Artificial Intelligence

- Python 3.11
- TensorFlow 2.x
- Keras
- TensorFlow Lite
- NumPy
- Pandas
- SciPy
- Scikit-learn 1.2.0

## Sensors & Hardware

- Accelerometer
- Gyroscope
- Significant Motion Sensor
- Bluetooth Low Energy
- Smartwatch

## Flutter Packages

- `tflite_flutter: 0.11.0`
- `sensors_plus: 6.1.1`
- `flutter_blue_plus`
- `flutter_foreground_task`
- `shared_preferences`
- `firebase_database`
- `flutter_local_notifications`
- `telephony`
- `geolocator`

## Development

- Visual Studio Code
- Google Colab
- Android Studio

---

# 📚 Kullanılan Veri Setleri

## mHealth Dataset

İnsan aktivitesi tanıma ve hareket analizi için kullanılmıştır.

Model:

~~~text
2-Layer LSTM
64 → 64
12 Output Classes
~~~

Girdi:

~~~text
(1, 100, 12)
~~~

---

## PTB Diagnostic ECG Database

Kardiyak ECG analizi ve anomali sınıflandırması için kullanılmıştır.

Model:

~~~text
Conv1D → MaxPooling → LSTM → LSTM → Dense
~~~

Girdi:

~~~text
(1, 187, 1)
~~~

---

# 🔐 Gizlilik ve Veri Güvenliği

VitalGuard'ın temel tasarım hedeflerinden biri, gerçek zamanlı yapay zeka analizini mümkün olduğunca cihaz üzerinde gerçekleştirmektir.

Ham sensör verileri gerçek zamanlı analiz amacıyla doğrudan buluta gönderilmez.

Firebase kullanıldığında temel olarak olay geçmişi gibi bilgiler saklanabilir:

- Anomali türü
- Zaman bilgisi
- Konum bilgisi

Bu yaklaşım sayesinde sürekli ham sensör verisinin sunucuya aktarılmasının önüne geçilmesi hedeflenmektedir.

---

# 🧩 Kullanılan Ana Bileşenler

### AI Service

TensorFlow Lite modellerini yükler ve inference işlemlerini gerçekleştirir.

### Sensor Service

Accelerometer ve Gyroscope verilerini toplar.

### BLE Service

Akıllı saat ve diğer BLE cihazlarıyla iletişim kurar.

### Emergency Service

Acil durum doğrulamasını, GPS konumunu ve SMS gönderimini yönetir.

### Monitoring Controller

Uygulamanın genel izleme durumunu yönetir ve servisler arasındaki koordinasyonu sağlar.

### Storage Helper

Kullanıcı tercihleri ve uygulama verilerinin yerel olarak saklanmasını sağlar.

---

# 🧠 Neden LSTM?

İnsan hareketleri ve ECG sinyalleri yalnızca tek bir anlık ölçümden oluşmaz.

Zamansal ilişkiler önemlidir.

Örneğin:

~~~text
t1 → t2 → t3 → t4 → t5 → ...
~~~

Bir hareketin veya ECG sinyalinin anlamı yalnızca tek bir örnek üzerinden değil, zaman içerisindeki değişimi üzerinden değerlendirilebilir.

LSTM mimarisi bu zamansal ilişkileri öğrenebilmesi nedeniyle projede tercih edilmiştir.

ECG modelinde ise Conv1D katmanı ile sinyalin yerel özellikleri çıkarıldıktan sonra LSTM katmanları zamansal ilişkileri öğrenmektedir.

---

# 📈 Sistem Akışı

~~~text
                  ┌─────────────────────┐
                  │   Mobile Sensors    │
                  │ Accelerometer       │
                  │ Gyroscope           │
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │   Sensor Service    │
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │   Data Processing   │
                  └──────────┬──────────┘
                             │
                  ┌──────────┴──────────┐
                  │                     │
                  ▼                     ▼
         ┌────────────────┐     ┌────────────────┐
         │  LSTM Model    │     │ Conv1D + LSTM  │
         │   mHealth      │     │      ECG       │
         └───────┬────────┘     └───────┬────────┘
                 │                      │
                 ▼                      ▼
         Activity / Fall         Cardiac Analysis
                 │                      │
                 └──────────┬───────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Anomaly Event │
                    └───────┬───────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ 12s Confirm.  │
                    └───────┬───────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Emergency     │
                    │ Protocol      │
                    └───────┬───────┘
                            │
                  ┌─────────┴─────────┐
                  │                   │
                  ▼                   ▼
              GPS / SMS          BLE Alarm
~~~

---

# ⚙️ Kurulum

## Gereksinimler

Kurulum öncesinde aşağıdakilerin sisteminizde bulunması gerekir:

- Flutter 3.x
- Dart 3.5
- Android Studio
- Android SDK
- Python 3.11
- Git

---

## Repository'yi Klonlama

~~~bash
git clone https://github.com/muhametaliaslanhan/LSTM-Tabanli-Mobil-Saglik-Sistemi-ile-Aktivite-Dusme-ve-Kardiyak-Aritmi-Tespiti.git
~~~

Projeye girin:

~~~bash
cd LSTM-Tabanli-Mobil-Saglik-Sistemi-ile-Aktivite-Dusme-ve-Kardiyak-Aritmi-Tespiti/bitirme_mobil
~~~

Flutter bağımlılıklarını yükleyin:

~~~bash
flutter pub get
~~~

Uygulamayı çalıştırın:

~~~bash
flutter run
~~~

---

# 📱 Android Cihazda Çalıştırma

Gerçek sensör verileri ve arka plan izleme özellikleri nedeniyle projenin fiziksel bir Android cihaz üzerinde test edilmesi önerilir.

Özellikle aşağıdaki özellikler gerçek cihaz üzerinde test edilmelidir:

- Accelerometer
- Gyroscope
- Significant Motion Sensor
- GPS
- SMS
- Bluetooth
- Foreground Service
- TensorFlow Lite inference

---

# ⚠️ Tıbbi Sorumluluk Reddi

VitalGuard bir **akademik ve prototip amaçlı araştırma projesidir**.

Sistem tarafından gerçekleştirilen aktivite, düşme veya kardiyak anomali tespitleri profesyonel tıbbi teşhis yerine geçmez.

Uygulama:

- Tıbbi teşhis
- Tedavi
- Profesyonel sağlık hizmeti
- Acil servis

yerine geçmez.

Gerçek bir sağlık probleminde mutlaka sağlık profesyonellerine başvurulmalıdır.

---

# 🔮 Gelecekte Yapılabilecek Geliştirmeler

- Daha fazla ECG sınıfının desteklenmesi
- Daha geniş ve çeşitli veri setleriyle eğitim
- Quantization ve pruning optimizasyonlarının geliştirilmesi
- Daha düşük enerji tüketimi
- Daha gelişmiş false-positive filtreleri
- Daha fazla smartwatch desteği
- Wear OS entegrasyonu
- Daha gelişmiş kullanıcı profilleri
- Bulut tabanlı uzun dönemli sağlık analizi
- Model güncelleme altyapısı
- Federated Learning araştırmaları
- Daha gelişmiş kişiselleştirilmiş eşik değerleri

---

# 🎓 Akademik Proje

Bu proje,

**Nevşehir Hacı Bektaş Veli Üniversitesi**  
**Mühendislik Fakültesi**  
**Bilgisayar Mühendisliği Bölümü**

kapsamında gerçekleştirilen bitirme projesidir.

### Proje Adı

**LSTM Tabanlı Akıllı Sağlık ve Kaza Takip Sistemi: Cihaz Üzerinde Yapay Zeka Destekli Mobil Uygulama**

---

# 👨‍💻 Geliştirici

**Muhammet Ali Aslanhan**

Computer Engineering

GitHub:

https://github.com/muhametaliaslanhan

---

# 🔗 Repository

Projenin kaynak kodlarına GitHub üzerinden ulaşabilirsiniz:

https://github.com/muhametaliaslanhan/LSTM-Tabanli-Mobil-Saglik-Sistemi-ile-Aktivite-Dusme-ve-Kardiyak-Aritmi-Tespiti

---

# ⭐ Projeyi Destekle

Projeyi faydalı bulduysanız GitHub repository'sine ⭐ bırakabilirsiniz.

---

<p align="center">
  <strong>VitalGuard</strong>
  <br>
  On-Device AI for Smarter Health & Safety
</p>
