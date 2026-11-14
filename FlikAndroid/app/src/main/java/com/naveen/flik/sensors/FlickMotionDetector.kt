package com.naveen.flik.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

class FlickMotionDetector(
    private val context: Context,
    private val onFlickDetected: (angle: Float, velocity: Float, aimX: Float) -> Unit
) : SensorEventListener {

    private val tag = "FlickMotionDetector"
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    
    private val linearAccelSensor = sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
        ?: sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

    private var lastFlickTime = 0L
    private val debounceMs = 1000L

    // Motion threshold calibration
    private val accelThreshold = 12.0f // m/s^2
    private val gyroThreshold = 3.5f   // rad/s

    private var currentGyroPitch = 0f
    private var currentGyroRoll = 0f

    fun startListening() {
        linearAccelSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        gyroSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
    }

    fun stopListening() {
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return

        when (event.sensor.type) {
            Sensor.TYPE_GYROSCOPE -> {
                currentGyroPitch = event.values[0] // Rotation around X-axis (pitch)
                currentGyroRoll = event.values[1]  // Rotation around Y-axis (roll)
            }
            Sensor.TYPE_LINEAR_ACCELERATION, Sensor.TYPE_ACCELEROMETER -> {
                val ax = event.values[0]
                val ay = event.values[1]
                val az = event.values[2]

                // Total forward / upward acceleration magnitude
                val forwardMagnitude = Math.sqrt((ay * ay + az * az).toDouble()).toFloat()

                val now = System.currentTimeMillis()
                if (now - lastFlickTime > debounceMs) {
                    // Check if both forward acceleration and pitch rotation exceed flick threshold
                    if (forwardMagnitude > accelThreshold && Math.abs(currentGyroPitch) > gyroThreshold) {
                        lastFlickTime = now

                        // Calculate flick angle based on roll tilt (-30 to +30 degrees)
                        val angle = (currentGyroRoll * 10f).coerceIn(-30f, 30f)
                        val velocity = (forwardMagnitude / 10f).coerceIn(1.0f, 2.5f)
                        val aimX = (angle / 25f).coerceIn(-1.0f, 1.0f)

                        Log.d(tag, "💥 Wrist Flick Detected! Angle: $angle°, Velocity: $velocity, AimX: $aimX")
                        triggerHaptic()
                        onFlickDetected(angle, velocity, aimX)
                    }
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun triggerHaptic() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator.vibrate(
                    VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK)
                )
            } else {
                @Suppress("DEPRECATION")
                val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                vibrator.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
            }
        } catch (e: Exception) {
            Log.e(tag, "Haptic vibration failed", e)
        }
    }
}
