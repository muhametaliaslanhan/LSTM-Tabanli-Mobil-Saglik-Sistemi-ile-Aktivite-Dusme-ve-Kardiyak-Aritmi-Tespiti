"""
mHealth Aktivite & Düşme Modeli — Eğitim + TFLite Dönüşümü
============================================================
Bu betik şu işleri tek seferde yapar:
  1. mHealth verisini okur (dinamik yol — kopyalandığı dizinde çalışır)
  2. LSTM modelini eğitir   (input shape: [1, 100, 12])
  3. Eğitilmiş modeli TFLite'a dönüştürür
  4. TFLite dosyasını Flutter assets klasörüne kopyalar

ÇALIŞTIRILMA:
  > python model_egitimi.py

ÇIKTILAR:
  - lstm_modelim.keras            (bu klasöre)
  - ../../lstm_saglik_kaza/assets/model.tflite  (Flutter assets'e)
"""

import pathlib, shutil
import pandas as pd
import numpy as np
from scipy import stats
from sklearn.preprocessing import OneHotEncoder
from sklearn.model_selection import train_test_split
import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout
from tensorflow.keras.activations import softmax

# ─────────────────────────────────────────────
# DİNAMİK YOL TANIMLARI — kopyaladığında da çalışır
# ─────────────────────────────────────────────
BETIK_DIZINI      = pathlib.Path(__file__).resolve().parent          # model/mhealth_model/
PROJE_KOKU        = BETIK_DIZINI.parent.parent                       # LSTM_tabanli_.../
VERI_SETI_YOLU    = PROJE_KOKU / "veri_setleri" / "mhealth_raw_data.csv"
KERAS_CIKTI       = BETIK_DIZINI / "lstm_modelim.keras"
FLUTTER_ASSETS    = PROJE_KOKU.parent / "lstm_saglik_kaza" / "assets"
TFLITE_CIKTI      = FLUTTER_ASSETS / "model.tflite"

# ─────────────────────────────────────────────
# PENCERE & ADIM PARAMETRELERİ
# Mobil tarafta da aynı değerler kullanılıyor!
#   TIME_STEPS = 100 satır (yaklaşık 5 saniyelik veri @20Hz)
#   STEP       = 50  (pencereler yarım yarıya örtüşüyor)
# ─────────────────────────────────────────────
TIME_STEPS = 100
STEP       = 50

# ─────────────────────────────────────────────
# KULLANILAN 12 SÜTUN (mobil ile eşleşen sensörler)
# mHealth veri setindeki tam sütun adları:
#   Göğüs ivmeölçer (3)   : acc_chest_x, acc_chest_y, acc_chest_z
#   Göğüs jiroskop  (3)   : gyro_chest_x, gyro_chest_y, gyro_chest_z
#   Sol ayak bileği (3)   : acc_ankle_left_x, acc_ankle_left_y, acc_ankle_left_z
#   Sol bileği jiro (3)   : gyro_ankle_left_x, gyro_ankle_left_y, gyro_ankle_left_z
# ─────────────────────────────────────────────
KULLANILAN_SUTUNLAR = [
    "acc_chest_x",       "acc_chest_y",       "acc_chest_z",
    "gyro_chest_x",      "gyro_chest_y",      "gyro_chest_z",
    "acc_ankle_left_x",  "acc_ankle_left_y",  "acc_ankle_left_z",
    "gyro_ankle_left_x", "gyro_ankle_left_y", "gyro_ankle_left_z",
    "Activity"  # etiket sütunu — işlem sonrası ayrılacak
]

# ─────────────────────────────────────────────
# VERİ OKUMA
# ─────────────────────────────────────────────
print(f"\n📂 Veri okunuyor: {VERI_SETI_YOLU}")
if not VERI_SETI_YOLU.exists():
    raise FileNotFoundError(
        f"Veri seti bulunamadı: {VERI_SETI_YOLU}\n"
        "Lütfen 'mhealth_raw_data.csv' dosyasının veri_setleri/ klasöründe olduğunu kontrol edin."
    )

aktivite_verileri = pd.read_csv(VERI_SETI_YOLU)
print("✅ Veri yüklendi.")
print(aktivite_verileri.info())
print("Eksik değerler:\n", aktivite_verileri.isnull().sum())

# Activity==0 → 'yok' etiketi, eğitimden çıkarılıyor
aktivite_verileri = aktivite_verileri[aktivite_verileri["Activity"] != 0].copy()

# 'subject' sütununu düşür (kişi ID'si, özellik değil)
if "subject" in aktivite_verileri.columns:
    aktivite_verileri = aktivite_verileri.drop("subject", axis=1)

# ─────────────────────────────────────────────
# SÜTUN SEÇİMİ
# CSV'de 24 sütun var (subject dahil). subject düştükten sonra 23 sütun kalıyor.
# Modelimiz 12 özellik bekliyor, bu yüzden KULLANILAN_SUTUNLAR'a göre filtrele.
# Eğer CSV'de bu sütun adları farklıysa, aşağıdaki fallback pozisyon bazlı seçimi kullanır.
# ─────────────────────────────────────────────
hedef_sutunlar = [s for s in KULLANILAN_SUTUNLAR if s != "Activity"]

if all(col in aktivite_verileri.columns for col in hedef_sutunlar):
    print("\n✅ Sütunlar isimleriyle seçildi.")
    x = aktivite_verileri[hedef_sutunlar]
else:
    # Fallback: pozisyon bazlı — ilk 12 özellik sütunu (subject ve Activity hariç)
    print("\n⚠️  Sütun adları eşleşmedi, pozisyon bazlı seçim yapılıyor (0-11. sütunlar).")
    ozellik_sutunlari = [c for c in aktivite_verileri.columns if c != "Activity"]
    x = aktivite_verileri[ozellik_sutunlari[:12]]

y = aktivite_verileri["Activity"]

# ─────────────────────────────────────────────
# ÖLÇEKLENDİRME — KAPATILDI (mobil uyumluluğu için)
# StandardScaler kapatıldı çünkü telefonda fit_transform yapamayız.
# Model ham değerlerle eğitildiğinde, mobil taraf da ham değer gönderir → tutarlı.
# ─────────────────────────────────────────────
x_islenmis = x.values
print(f"\n📊 Özellik matrisi boyutu: {x_islenmis.shape}")
print(f"   İlk satır örneği: {x_islenmis[0]}")

# ─────────────────────────────────────────────
# PENCERE (WINDOWING) İŞLEMİ
# Mobil taraftaki SensorIslemci.dart ile AYNI mantık:
#   - Her 50ms'de bir örnek toplanıyor
#   - 100 örnek = 1 pencere = LSTM'e 1 tahmin
# ─────────────────────────────────────────────
xs, ys = [], []
for i in range(0, len(x_islenmis) - TIME_STEPS, STEP):
    v      = x_islenmis[i : i + TIME_STEPS]
    labels = y.iloc[i : i + TIME_STEPS]
    xs.append(v)
    ys.append(stats.mode(labels, keepdims=True)[0][0])

X_son = np.array(xs)
y_son = np.array(ys).reshape(-1, 1)
y_son = pd.DataFrame(y_son)

print(f"\n✅ Pencere işlemi tamamlandı.")
print(f"   X_son boyutu: {X_son.shape}  → beklenen: (N, {TIME_STEPS}, 12)")
print(f"   y_son boyutu: {y_son.shape}")

# OneHot encoding
encoder   = OneHotEncoder(sparse_output=False)
y_encoder = encoder.fit_transform(y_son)
print(f"\n✅ Encoding tamamlandı: {y_encoder.shape}")
print(f"   Sınıf sayısı: {y_encoder.shape[1]}")
print(f"   Örnek etiket: {y_encoder[0]}")

# Train / Test ayrımı
x_train, x_test, y_train, y_test = train_test_split(
    X_son, y_encoder, random_state=42, test_size=0.20, stratify=y_encoder
)
print(f"\n📦 x_train: {x_train.shape}  |  x_test: {x_test.shape}")
print(f"   y_train: {y_train.shape}  |  y_test: {y_test.shape}")

# ─────────────────────────────────────────────
# LSTM MODELİ
# Input shape: (TIME_STEPS=100, özellik=12)
# Çıktı: 12 aktivite sınıfı (mHealth L1–L12)
# ─────────────────────────────────────────────
n_sinif = y_encoder.shape[1]  # genellikle 12

model = Sequential([
    LSTM(units=64, return_sequences=True, input_shape=(TIME_STEPS, 12)),
    Dropout(0.5),
    LSTM(units=64, return_sequences=False),
    Dropout(0.5),
    Dense(units=n_sinif, activation=softmax),
])

model.summary()
model.compile(
    optimizer="adam",
    loss="categorical_crossentropy",
    metrics=["accuracy", tf.keras.metrics.Recall(), tf.keras.metrics.Precision()],
)

print("\n🚀 Eğitim başlıyor...")
history = model.fit(
    x_train, y_train,
    epochs=20,
    batch_size=64,
    validation_data=(x_test, y_test),
)

model.save(str(KERAS_CIKTI))
print(f"\n✅ Keras modeli kaydedildi: {KERAS_CIKTI}")

# ─────────────────────────────────────────────
# TFLITE DÖNÜŞÜMÜ — Sabit input shape ile
# Flutter tflite_flutter paketi dinamik shape sevmez,
# bu yüzden batch_size=1 olarak sabitleniyor.
# ─────────────────────────────────────────────
print("\n🔄 TFLite dönüşümü başlıyor...")

sabit_giris  = tf.keras.layers.Input(batch_shape=(1, TIME_STEPS, 12))
sabit_cikis  = model(sabit_giris)
sabit_model  = tf.keras.Model(sabit_giris, sabit_cikis)

converter = tf.lite.TFLiteConverter.from_keras_model(sabit_model)
converter.target_spec.supported_ops = [
    tf.lite.OpsSet.TFLITE_BUILTINS,
    tf.lite.OpsSet.SELECT_TF_OPS,
]
converter._experimental_lower_tensor_list_ops = False

tflite_model = converter.convert()

# Flutter assets klasörü yoksa oluştur
FLUTTER_ASSETS.mkdir(parents=True, exist_ok=True)

with open(TFLITE_CIKTI, "wb") as f:
    f.write(tflite_model)

print(f"✅ TFLite modeli kaydedildi: {TFLITE_CIKTI}")
print(f"   Dosya boyutu: {TFLITE_CIKTI.stat().st_size / 1024:.1f} KB")
print("\n🎉 Tüm işlemler tamamlandı! Flutter assets klasörü güncellendi.")
print("   Şimdi 'ecg_model_egitimi.py' dosyasını çalıştırabilirsiniz.")