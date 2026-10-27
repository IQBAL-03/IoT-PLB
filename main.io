#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <WiFiClient.h>

// Template Blynk ID
#define BLYNK_TEMPLATE_ID   "TMPL6vZWOsUhH"
#define BLYNK_TEMPLATE_NAME "Plant Watering System"

#include <BlynkSimpleEsp32.h>  // Include setelah macro di atas

// Pin dan threshold
#define SENSOR_PIN 33
#define RELAY_PIN  4
#define THRESHOLD  50  // % kelembapan di bawah ini pompa menyala

LiquidCrystal_I2C lcd(0x27, 16, 2);
BlynkTimer timer;

// Auth & WiFi
char auth[] = "dKpUYSW9CoruTAYJMQa82CBf-VyH4h42";
char ssid[] = "haniin";
char pass[] = "barcamenangucl";

void setup() {
  Serial.begin(115200);
  Blynk.begin(auth, ssid, pass, "blynk.cloud", 80);

  lcd.init();
  lcd.backlight();
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH); // Matikan pompa awal

  // Tampilan loading
  lcd.setCursor(1, 0);
  lcd.print("System Loading");
  for (int a = 0; a <= 15; a++) {
    lcd.setCursor(a, 1);
    lcd.print(".");
    delay(100);
  }
  lcd.clear();

  // Jadwalkan pembacaan sensor tiap 2 detik
  timer.setInterval(2000L, soilMoisture);
}

void soilMoisture() {
  int raw      = analogRead(SENSOR_PIN);
  int moisture = map(raw, 0, 4095, 0, 100);
  moisture     = constrain(moisture, 0, 100);

  Blynk.virtualWrite(V0, moisture);
  Serial.printf("Soil Moisture: %d%%\n", moisture);

  lcd.setCursor(0, 0);
  lcd.print("Moisture: ");
  lcd.print(moisture);
  lcd.print("%  ");

  if (moisture < THRESHOLD) {
    digitalWrite(RELAY_PIN, LOW);   // Nyalakan pompa
    lcd.setCursor(0, 1);
    lcd.print("Pompa: ON  ");
    Blynk.virtualWrite(V1, 1);
  } else {
    digitalWrite(RELAY_PIN, HIGH);  // Matikan pompa
    lcd.setCursor(0, 1);
    lcd.print("Pompa: OFF ");
    Blynk.virtualWrite(V1, 0);
  }
}

void loop() {
  Blynk.run();
  timer.run();
}
