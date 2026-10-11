"""
ECG Kalp Aritmisi Modeli — Eğitim + TFLite Dönüşümü
=====================================================
Bu betik şu işleri tek seferde yapar:
  1. ptbdb_normal.csv + ptbdb_abnormal.csv verilerini okur (dinamik yol)
  2. Conv1D + LSTM modelini eğitir   (input shape: [1, 187, 1])
  3. Eğitilmiş modeli TFLite'a dönüştürür (sabit batch_shape)
  4. TFLite dosyasını Flutter assets klasörüne kopyalar

ÇALIŞTIRILMA:
  > python ecg_model_egitimi.py

ÇIKTILAR:
  - kalp_aritmi_modelim.keras          (bu klasöre)
  - ../../lstm_saglik_kaza/assets/kalp_aritmi_model_mobil_saf.tflite  (Flutter assets'e)

MODEL GİRİŞ FORMATI (Dart tarafında beklenen):
  var input = [[[ [v0], [v1], ..., [v186] ]]]   → shape: [1, 187, 1]
"""

import pathlib
import pandas as pd
import numpy as np
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.utils.class_weight import compute_class_weight
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout, Conv1D, MaxPooling1D
from tensorflow.keras.callbacks import ReduceLROnPlateau, EarlyStopping

# ─────────────────────────────────────────────
# DİNAMİK YOL TANIMLARI
# ─────────────────────────────────────────────
BETIK_DIZINI   = pathlib.Path(__file__).resolve().parent          # model/ecg_model/
PROJE_KOKU     = BETIK_DIZINI.parent.parent                       # LSTM_tabanli_.../
ECG_KLASORU    = PROJE_KOKU / "veri_setleri" / "ECG_veri_seti_dosyalari"
NORMAL_CSV     = ECG_KLASORU / "ptbdb_normal.csv"
ANORMAL_CSV    = ECG_KLASORU / "ptbdb_abnormal.csv"
KERAS_CIKTI    = BETIK_DIZINI / "kalp_aritmi_modelim.keras"
FLUTTER_ASSETS = PROJE_KOKU.parent / "lstm_saglik_kaza" / "assets"
TFLITE_CIKTI   = FLUTTER_ASSETS / "kalp_aritmi_model_mobil_saf.tflite"

# ─────────────────────────────────────────────
# VERİ OKUMA
# ─────────────────────────────────────────────
print(f"\n📂 Normal ECG okunuyor  : {NORMAL_CSV}")
print(f"📂 Anormal ECG okunuyor : {ANORMAL_CSV}")

for yol in [NORMAL_CSV, ANORMAL_CSV]:
    if not yol.exists():
        raise FileNotFoundError(
            f"Veri seti bulunamadı: {yol}\n"
            "Lütfen 'ECG_veri_seti_dosyalari' klasörünün doğru yerde olduğunu kontrol edin."
        )

normal_df  = pd.read_csv(NORMAL_CSV,  header=None)
anormal_df = pd.read_csv(ANORMAL_CSV, header=None)

birlesmis = pd.concat([normal_df, anormal_df], axis=0)
print(f"\n✅ Veri birleştirildi. Toplam boyut: {birlesmis.shape}")

# Karıştır
birlesmis = birlesmis.sample(frac=1, random_state=42).reset_index(drop=True)

# ─────────────────────────────────────────────
# ÖZELLİK / ETİKET AYRIMI
# PTB-DB formatı: ilk 187 sütun = EKG sinyali, son sütun = etiket (0:normal, 1:anormal)
# ─────────────────────────────────────────────
x_verileri = birlesmis.iloc[:, :187].to_numpy()
y_verileri = birlesmis.iloc[:, -1].to_numpy()

print(f"   x_verileri: {x_verileri.shape}  → EKG sinyal değerleri")
print(f"   y_verileri: {y_verileri.shape}  → 0=Normal, 1=Anormal")
print(f"   Sınıf dağılımı: Normal={int((y_verileri==0).sum())}  |  Anormal={int((y_verileri==1).sum())}")

# ─────────────────────────────────────────────
# RESHAPE — Conv1D ve LSTM için [N, 187, 1] gerekiyor
# Mobil tarafta da bu shape beklendiğinden kritik!
# ─────────────────────────────────────────────
x_verileri = x_verileri.reshape(x_verileri.shape[0], 187, 1)
y_verileri = y_verileri.reshape(-1, 1)

# Train / Test ayrımı
x_egitim, x_test, y_egitim, y_test = train_test_split(
    x_verileri, y_verileri, random_state=42, test_size=0.2, stratify=y_verileri
)
print(f"\n📦 x_egitim: {x_egitim.shape}  |  x_test: {x_test.shape}")

# ─────────────────────────────────────────────
# MODEL — Conv1D + LSTM Hibrit
# Conv1D: kısa süreli EKG desenlerini yakalar
# LSTM  : zamansal bağımlılıkları öğrenir
# ─────────────────────────────────────────────
model = Sequential([
    Conv1D(filters=32, kernel_size=3, activation="relu", input_shape=(187, 1)),
    MaxPooling1D(pool_size=2),
    LSTM(units=64, return_sequences=True),
    Dropout(0.2),
    LSTM(units=64, return_sequences=False),
    Dropout(0.2),
    Dense(units=1, activation="sigmoid"),
])

model.summary()
model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
    loss="binary_crossentropy",
    metrics=["accuracy", tf.keras.metrics.Recall(), tf.keras.metrics.Precision()],
)

# Sınıf ağırlıkları — veri dengesizliğini gider
siniflar = np.unique(y_egitim)
agirliklar = compute_class_weight(
    class_weight="balanced", classes=siniflar, y=y_egitim.flatten()
)
sozluk_agirlik = dict(zip(siniflar, agirliklar))
print(f"\n⚖️  Sınıf ağırlıkları: {sozluk_agirlik}")

# Callbacks
geri_cagir    = ReduceLROnPlateau(monitor="val_loss", factor=0.2, patience=5, min_lr=0.0001, verbose=1)
erken_durdur  = EarlyStopping(monitor="val_loss", patience=10, restore_best_weights=True, verbose=1)

print("\n🚀 Eğitim başlıyor (max 100 epoch, EarlyStopping aktif)...")
model.fit(
    x_egitim, y_egitim,
    epochs=100,
    batch_size=64,
    validation_data=(x_test, y_test),
    callbacks=[geri_cagir, erken_durdur],
    class_weight=sozluk_agirlik,
)

model.save(str(KERAS_CIKTI))
print(f"\n✅ Keras modeli kaydedildi: {KERAS_CIKTI}")

# ─────────────────────────────────────────────
# TFLITE DÖNÜŞÜMÜ
# Sabit input shape: (1, 187, 1)
#   batch_size = 1  → mobil çıkarım için zorunlu
#   187         → EKG sinyal uzunluğu
#   1           → kanal (tek boyutlu sinyal)
# ─────────────────────────────────────────────
print("\n🔄 TFLite dönüşümü başlıyor...")

sabit_giris = tf.keras.layers.Input(batch_shape=(1, 187, 1))
sabit_cikis = model(sabit_giris)
sabit_model = tf.keras.Model(sabit_giris, sabit_cikis)

converter = tf.lite.TFLiteConverter.from_keras_model(sabit_model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
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
print("   Artık 'flutter run' komutuyla uygulamayı başlatabilirsiniz.")