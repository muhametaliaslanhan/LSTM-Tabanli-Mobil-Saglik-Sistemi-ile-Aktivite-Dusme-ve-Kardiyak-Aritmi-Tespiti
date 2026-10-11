"""
ECG Kalp Aritmisi modeli — TFLite dönüştürücü (Yedek / Bağımsız çalıştırma)
NOT: ecg_model_egitimi.py zaten TFLite dönüşümünü içeriyor.
Bu dosya sadece mevcut .keras modelini yeniden dönüştürmek istersen kullanılır.
"""
import pathlib
import tensorflow as tf

BETIK_DIZINI   = pathlib.Path(__file__).resolve().parent
PROJE_KOKU     = BETIK_DIZINI.parent.parent
KERAS_YOLU     = BETIK_DIZINI / "kalp_aritmi_modelim.keras"
FLUTTER_ASSETS = PROJE_KOKU.parent / "lstm_saglik_kaza" / "assets"
TFLITE_CIKTI   = FLUTTER_ASSETS / "kalp_aritmi_model_mobil_saf.tflite"

print(f"📂 Model yükleniyor: {KERAS_YOLU}")
try:
    model = tf.keras.models.load_model(str(KERAS_YOLU))
    print("✅ Model başarıyla yüklendi!")
except Exception as e:
    raise RuntimeError(f"Model yüklenemedi: {e}")

# Sabit batch_shape=(1,187,1) ile yeniden sarmalama
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

FLUTTER_ASSETS.mkdir(parents=True, exist_ok=True)
with open(TFLITE_CIKTI, "wb") as f:
    f.write(tflite_model)

print(f"✅ TFLite dönüşümü tamamlandı: {TFLITE_CIKTI}")
print(f"   Dosya boyutu: {TFLITE_CIKTI.stat().st_size / 1024:.1f} KB")