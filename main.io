#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <WiFi.h>
#include <WiFiManager.h>      // Library WiFiManager by tzapu (install via Arduino Library Manager)
#include <Preferences.h>      // Built-in ESP32 Non-Volatile Storage (Flash)

#define BLYNK_TEMPLATE_ID   "TMPL6vZWOsUhH"
#define BLYNK_TEMPLATE_NAME "Plant Watering System"

#include <BlynkSimpleEsp32.h>

// ─── Pin Definitions ──────────────────────────────────────────────────────────
#define SENSOR_PIN       33    // Analog pin sensor kelembapan tanah
#define RELAY_PIN        4     // Pin relay pompa air
#define RESET_BTN_PIN    0     // Pin tombol BOOT built-in ESP32 (tekan 5 detik untuk reset WiFi)
#define THRESHOLD        50    // Ambang batas kelembapan default (50%)

LiquidCrystal_I2C lcd(0x27, 16, 2);
BlynkTimer timer;
Preferences preferences;

// ─── Identitas Unik Perangkat (Auto-Generated dari Chip MAC) ──────────────────
char deviceId[20];
char pairingCode[10] = "8821"; // Kode pairing default (bisa diubah via portal)
char blynkAuth[40]   = "dKpUYSW9CoruTAYJMQa82CBf-VyH4h42"; // Default token

bool shouldSaveConfig = false;

// Callback saat user menyimpan konfigurasi baru di WiFiManager portal
void saveConfigCallback() {
  Serial.println("[PlantCare] Pengguna menyimpan konfigurasi baru via portal.");
  shouldSaveConfig = true;
}

// Inisialisasi Device ID unik dari MAC Address ESP32
void initDeviceId() {
  uint64_t chipid = ESP.getEfuseMac();
  uint16_t id1 = (uint16_t)(chipid >> 32);
  uint16_t id2 = (uint16_t)(chipid);
  snprintf(deviceId, sizeof(deviceId), "PLB-%04X%04X", id1, id2);
  Serial.printf("[PlantCare] Unique Device ID: %s\n", deviceId);
}

// Membaca atau memuat konfigurasi dari Flash NVS
void loadStoredConfig() {
  preferences.begin("plantcare", false);
  String savedAuth = preferences.getString("blynk_auth", "");
  String savedPair = preferences.getString("pairing_code", "");

  if (savedAuth.length() > 0) {
    savedAuth.toCharArray(blynkAuth, sizeof(blynkAuth));
  }
  if (savedPair.length() > 0) {
    savedPair.toCharArray(pairingCode, sizeof(pairingCode));
  }
  preferences.end();
}

void saveStoredConfig(const char* newAuth, const char* newPair) {
  preferences.begin("plantcare", false);
  preferences.putString("blynk_auth", newAuth);
  preferences.putString("pairing_code", newPair);
  preferences.end();
  Serial.println("[PlantCare] Konfigurasi berhasil disimpan ke NVS Flash.");
}

// Setup WiFiManager dengan portal interaktif HP
void setupWiFiManager() {
  WiFiManager wm;
  wm.setSaveConfigCallback(saveConfigCallback);
  wm.setConfigPortalTimeout(180); // Timeout 3 menit jika tidak ada yg konek

  // Custom input fields di halaman portal HP
  WiFiManagerParameter custom_blynk_auth("blynk", "Blynk Auth Token", blynkAuth, 36);
  WiFiManagerParameter custom_pairing_code("pair", "Pairing Code Unit", pairingCode, 8);

  wm.addParameter(&custom_blynk_auth);
  wm.addParameter(&custom_pairing_code);

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Konek Hotspot:");
  lcd.setCursor(0, 1);
  lcd.print("PlantCare-Setup");

  // Nama Hotspot AP yang dipancarkan oleh ESP32
  String apName = "PlantCare-" + String(deviceId).substring(strlen(deviceId) - 4);
  Serial.printf("[PlantCare] Memancarkan hotspot: %s (IP: 192.168.4.1)\n", apName.c_str());

  // AutoConnect: jika WiFi rumah lama terdeteksi langsung konek; jika tidak, buka hotspot portal
  if (!wm.autoConnect(apName.c_str())) {
    Serial.println("[PlantCare] Gagal konek ke WiFi / Timeout. Masuk mode offline lokal.");
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("Mode: Offline");
    lcd.setCursor(0, 1);
    lcd.print("Otomatis Lokal");
    delay(2000);
  } else {
    Serial.println("[PlantCare] Berhasil terhubung ke WiFi!");
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("WiFi Terhubung!");
    lcd.setCursor(0, 1);
    lcd.print(WiFi.localIP().toString());
    delay(2000);
  }

  // Jika user memasukkan parameter baru di portal, simpan ke Flash
  if (shouldSaveConfig) {
    saveStoredConfig(custom_blynk_auth.getValue(), custom_pairing_code.getValue());
    strncpy(blynkAuth, custom_blynk_auth.getValue(), sizeof(blynkAuth));
    strncpy(pairingCode, custom_pairing_code.getValue(), sizeof(pairingCode));
  }
}

// Cek tombol reset WiFi fisik (Tekan tombol BOOT selama 5 detik)
void checkResetButton() {
  if (digitalRead(RESET_BTN_PIN) == LOW) {
    Serial.println("[PlantCare] Tombol reset ditekan, tahan 5 detik untuk reset WiFi...");
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("Tahan 5 detik");
    lcd.setCursor(0, 1);
    lcd.print("Untuk Reset WiFi");

    unsigned long startPress = millis();
    while (digitalRead(RESET_BTN_PIN) == LOW) {
      if (millis() - startPress > 5000) {
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print("WiFi Direset!");
        lcd.setCursor(0, 1);
        lcd.print("Rebooting...");
        Serial.println("[PlantCare] WiFi Direset! Menghapus data jaringan...");
        WiFiManager wm;
        wm.resetSettings();
        delay(2000);
        ESP.restart();
      }
      delay(50);
    }
  }
}

void soilMoisture() {
  int raw      = analogRead(SENSOR_PIN);
  int moisture = map(raw, 0, 4095, 0, 100);
  moisture     = constrain(moisture, 0, 100);

  // Update LCD
  lcd.setCursor(0, 0);
  lcd.print("Mst:");
  lcd.print(moisture);
  lcd.print("% ");
  lcd.print(deviceId);

  bool pumpOn = false;
  if (moisture < THRESHOLD) {
    digitalWrite(RELAY_PIN, LOW); // Aktif (Low-Trigger Relay)
    pumpOn = true;
    lcd.setCursor(0, 1);
    lcd.print("Pompa: ON [AUTO] ");
  } else {
    digitalWrite(RELAY_PIN, HIGH); // Mati
    pumpOn = false;
    lcd.setCursor(0, 1);
    lcd.print("Pompa: OFF[AUTO] ");
  }

  // Jika tersambung ke Blynk & WiFi, sinkronkan data ke Cloud
  if (WiFi.status() == WL_CONNECTED && Blynk.connected()) {
    Blynk.virtualWrite(V0, moisture);
    Blynk.virtualWrite(V1, pumpOn ? 1 : 0);
  }
  Serial.printf("[Sensor] Moisture: %d%% | Pompa: %s\n", moisture, pumpOn ? "ON" : "OFF");
}

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(RESET_BTN_PIN, INPUT_PULLUP);
  digitalWrite(RELAY_PIN, HIGH); // Standby mati

  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("PlantCare System");
  lcd.setCursor(0, 1);
  lcd.print("Initializing...");
  delay(1000);

  initDeviceId();
  loadStoredConfig();
  setupWiFiManager();

  // Hubungkan ke Blynk Cloud jika WiFi tersedia
  if (WiFi.status() == WL_CONNECTED) {
    Blynk.config(blynkAuth, "blynk.cloud", 80);
    Blynk.connect(5000); // Timeout 5 detik agar tidak memblokir sistem
  }

  timer.setInterval(2000L, soilMoisture);
}

void loop() {
  // Jalankan tombol reset listener
  checkResetButton();

  // Jalankan Blynk hanya jika WiFi tersambung
  if (WiFi.status() == WL_CONNECTED) {
    Blynk.run();
  }

  timer.run();
}
