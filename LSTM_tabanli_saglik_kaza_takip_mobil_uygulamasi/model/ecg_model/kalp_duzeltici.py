"""
ECG modeli — Optimize edilmiş TFLite dönüştürücü (Yedek / Bağımsız çalıştırma)
NOT: ecg_model_egitimi.py zaten TFLite dönüşümünü içeriyor.
Bu dosya sadece yüksek optimizasyon (tam tamsayı kuantizasyon) istersen kullanılır.
"""
import pathlib
import tensorflow as tf

BETIK_DIZINI   = pathlib.Path(__file__).resolve().parent
PROJE_KOKU     = BETIK_DIZINI.parent.parent
KERAS_YOLU     = BETIK_DIZINI / "kalp_aritmi_modelim.keras"
FLUTTER_ASSETS = PROJE_KOKU.parent / "lstm_saglik_kaza" / "assets"
TFLITE_CIKTI   = FLUTTER_ASSETS / "kalp_aritmi_model_mobil_saf.tflite"

print(f"📂 Model yükleniyor: {KERAS_YOLU}")
model = tf.keras.models.load_model(str(KERAS_YOLU))

# Sabit shape ile sarmalama
sabit_giris = tf.keras.layers.Input(batch_shape=(1, 187, 1))
sabit_cikis = model(sabit_giris)
sabit_model = tf.keras.Model(sabit_giris, sabit_cikis)

converter = tf.lite.TFLiteConverter.from_keras_model(sabit_model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]

tflite_model = converter.convert()

FLUTTER_ASSETS.mkdir(parents=True, exist_ok=True)
with open(TFLITE_CIKTI, "wb") as f:
    f.write(tflite_model)

print(f"✅ Optimize TFLite dönüşümü tamamlandı: {TFLITE_CIKTI}")
print(f"   Dosya boyutu: {TFLITE_CIKTI.stat().st_size / 1024:.1f} KB")
