package com.naveen.flik

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.widget.EditText
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.naveen.flik.databinding.ActivityMainBinding
import com.naveen.flik.discovery.DiscoveredMac
import com.naveen.flik.discovery.NsdDiscoveryManager
import com.naveen.flik.network.FlikPhoneServer
import com.naveen.flik.network.FlikTransferClient
import com.naveen.flik.sensors.FlickMotionDetector
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.io.File

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var discoveryManager: NsdDiscoveryManager
    private lateinit var transferClient: FlikTransferClient
    private lateinit var motionDetector: FlickMotionDetector
    private lateinit var phoneServer: FlikPhoneServer

    private var selectedDevice: DiscoveredMac? = null
    private var selectedUris = mutableListOf<Uri>()
    private var isTransferring = false
    private var mediaPlayer: MediaPlayer? = null

    private fun playFlickSound() {
        try {
            mediaPlayer?.release()
            mediaPlayer = MediaPlayer.create(this, R.raw.flick_sound)
            mediaPlayer?.start()
        } catch (e: Exception) {
            // Ignored
        }
    }

    private val mediaPickerLauncher = registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) {
            onFilesSelected(uris)
        }
    }

    private val filePickerLauncher = registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) {
            onFilesSelected(uris)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        discoveryManager = NsdDiscoveryManager(this)
        transferClient = FlikTransferClient(this)

        // Start reverse flick phone server (listen for files from Mac)
        phoneServer = FlikPhoneServer(this) { file, mimeType ->
            onFileReceivedFromMac(file, mimeType)
        }
        phoneServer.start()
        discoveryManager.registerPhoneService(phoneServer.port)

        setupUI()
        setupSensors()
        observeDiscovery()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupUI() {
        binding.btnPhotos.setOnClickListener {
            // Pick multiple photos or videos
            mediaPickerLauncher.launch(arrayOf("image/*", "video/*"))
        }

        binding.btnFiles.setOnClickListener {
            // Pick multiple files of any type
            filePickerLauncher.launch(arrayOf("*/*"))
        }

        binding.btnLink.setOnClickListener {
            showLinkDialog()
        }

        // Touch Drag & Flick Gesture on Card
        var startX = 0f
        var startY = 0f
        var velocityTracker: VelocityTracker? = null

        binding.flickCard.setOnTouchListener { view, event ->
            if (isTransferring || selectedUris.isEmpty()) return@setOnTouchListener false

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.rawX
                    startY = event.rawY
                    velocityTracker?.recycle()
                    velocityTracker = VelocityTracker.obtain()
                    velocityTracker?.addMovement(event)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    velocityTracker?.addMovement(event)
                    val deltaX = event.rawX - startX
                    val deltaY = (event.rawY - startY).coerceAtMost(100f)
                    view.translationX = deltaX
                    view.translationY = deltaY
                    view.rotation = (deltaX / 16f).coerceIn(-28f, 28f)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    velocityTracker?.addMovement(event)
                    velocityTracker?.computeCurrentVelocity(1000)
                    val vx = velocityTracker?.xVelocity ?: 0f
                    val vy = velocityTracker?.yVelocity ?: 0f
                    velocityTracker?.recycle()
                    velocityTracker = null

                    val currentY = view.translationY
                    val currentX = view.translationX

                    if (currentY < -160f || (currentY < -50f && vy < -700f)) {
                        // Calculate throw angle using atan2(deltaX, -deltaY)
                        val rawAngleRad = Math.atan2(currentX.toDouble(), (-currentY.coerceAtMost(-10f)).toDouble())
                        val flickAngleDeg = Math.toDegrees(rawAngleRad).toFloat().coerceIn(-35f, 35f)
                        
                        // Horizontal aiming ratio: -1.0 (left) to +1.0 (right)
                        val aimX = (currentX / 180f).coerceIn(-1.0f, 1.0f)
                        
                        // Velocity based on fling speed
                        val speedMag = Math.hypot(vx.toDouble(), vy.toDouble()).toFloat()
                        val flickVelocity = (speedMag / 1500f).coerceIn(1.0f, 2.5f)

                        // Launch card upward off screen along the throw trajectory
                        val flyX = currentX * 3.5f
                        playFlickSound()
                        view.animate()
                            .translationX(flyX)
                            .translationY(-1800f)
                            .rotation(flickAngleDeg * 1.3f)
                            .alpha(0.0f)
                            .setDuration(220)
                            .withEndAction {
                                // Trigger transfer with angle, velocity, aimX
                                performFlik(flickAngleDeg, flickVelocity, aimX)

                                // Reset card back into place
                                view.translationX = 0f
                                view.translationY = 500f
                                view.rotation = 0f
                                view.alpha = 0f
                                view.animate()
                                    .translationY(0f)
                                    .alpha(1.0f)
                                    .setDuration(300)
                                    .start()
                            }
                            .start()
                    } else {
                        // Snap back to rest position
                        view.animate()
                            .translationX(0f)
                            .translationY(0f)
                            .rotation(0f)
                            .setDuration(200)
                            .start()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun setupSensors() {
        motionDetector = FlickMotionDetector(this) { angle, velocity, aimX ->
            if (selectedUris.isNotEmpty() && !isTransferring) {
                performFlik(angle, velocity, aimX)
            } else if (selectedUris.isEmpty()) {
                runOnUiThread {
                    Toast.makeText(this, "Select photos or files first!", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun observeDiscovery() {
        lifecycleScope.launch {
            discoveryManager.devices.collectLatest { devices ->
                if (devices.isNotEmpty()) {
                    selectedDevice = devices.first()
                    binding.tvDeviceName.text = "${selectedDevice?.name} • Ready"
                    binding.viewOnlineDot.visibility = View.VISIBLE
                } else {
                    selectedDevice = null
                    binding.tvDeviceName.text = "Searching for nearby Mac..."
                    binding.viewOnlineDot.visibility = View.GONE
                }
            }
        }
    }

    private fun onFilesSelected(uris: List<Uri>) {
        if (uris.isEmpty()) return
        selectedUris.clear()
        selectedUris.addAll(uris)

        val count = selectedUris.size
        val firstUri = selectedUris.first()
        val firstName = getFileName(firstUri)

        if (count == 1) {
            binding.tvFileName.text = firstName
            binding.tvStatus.text = "Ready to Nox Flick: $firstName"
        } else {
            binding.tvFileName.text = "📚 $count files ($firstName + ${count - 1} more)"
            binding.tvStatus.text = "Ready to Nox Flick $count files"
        }

        // Preview thumbnail of first media
        try {
            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, firstUri))
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(contentResolver, firstUri)
            }
            binding.ivPreview.setImageBitmap(bitmap)
            binding.ivPreview.visibility = View.VISIBLE
        } catch (e: Exception) {
            binding.ivPreview.visibility = View.GONE
        }

        binding.layoutEmptyState.visibility = View.GONE
        binding.layoutCardBottom.visibility = View.VISIBLE
    }

    private fun performFlik(angle: Float, velocity: Float, aimX: Float = 0f) {
        val mac = selectedDevice ?: run {
            Toast.makeText(this, "Searching for nearby Mac...", Toast.LENGTH_SHORT).show()
            return
        }
        if (selectedUris.isEmpty()) return

        isTransferring = true
        val total = selectedUris.size
        binding.tvStatus.text = if (total == 1) "🚀 Flicking to ${mac.name}..." else "🚀 Flicking $total files to ${mac.name}..."

        lifecycleScope.launch {
            var allSuccess = true
            for (i in 0 until total) {
                val uri = selectedUris[i]
                val name = getFileName(uri)
                if (total > 1) {
                    binding.tvStatus.text = "🚀 Sending (${i + 1}/$total): $name..."
                }

                // Spatial cascade spread so cards land naturally fanned across screen
                val spread = if (total > 1) (i.toFloat() - (total - 1) / 2.0f) else 0f
                val fileAimX = (aimX + spread * 0.16f).coerceIn(-1.0f, 1.0f)
                val fileAngle = (angle + spread * 4.0f).coerceIn(-30f, 30f)

                val success = transferClient.streamFile(mac, uri, fileAngle, velocity, fileAimX)
                if (!success) allSuccess = false

                if (total > 1 && i < total - 1) {
                    kotlinx.coroutines.delay(120) // Smooth cascade arrival delay
                }
            }

            isTransferring = false
            if (allSuccess) {
                val msg = if (total == 1) "Delivered to ${mac.name}!" else "All $total files delivered to ${mac.name}!"
                binding.tvStatus.text = "🎉 $msg"
                Toast.makeText(this@MainActivity, msg, Toast.LENGTH_SHORT).show()
                selectedUris.clear()
                binding.ivPreview.visibility = View.GONE
                binding.layoutCardBottom.visibility = View.GONE
                binding.layoutEmptyState.visibility = View.VISIBLE
            } else {
                binding.tvStatus.text = "❌ Some transfers failed"
                Toast.makeText(this@MainActivity, "Transfer failed", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun showLinkDialog() {
        val input = EditText(this)
        input.hint = "https://example.com"
        input.setSingleLine()

        AlertDialog.Builder(this)
            .setTitle("Send Link to Mac")
            .setView(input)
            .setPositiveButton("Flick Link") { _, _ ->
                val link = input.text.toString().trim()
                if (link.isNotEmpty()) {
                    selectedDevice?.let { mac ->
                        lifecycleScope.launch {
                            binding.tvStatus.text = "Flicking link..."
                            val success = transferClient.sendLink(mac, link)
                            binding.tvStatus.text = if (success) "✨ Link opened on ${mac.name}!" else "❌ Failed to send link"
                        }
                    } ?: Toast.makeText(this, "No Mac connected", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun getFileName(uri: Uri): String {
        var name = "selected_file"
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index != -1 && cursor.moveToFirst()) {
                val displayName = cursor.getString(index)
                if (!displayName.isNullOrBlank()) name = displayName
            }
        }
        return name
    }

    private fun onFileReceivedFromMac(file: File, mimeType: String) {
        playFlickSound()

        // Haptic pulse feedback
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 100, 80, 120), -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(150)
            }
        } catch (e: Exception) {
            // Ignored
        }

        binding.tvStatus.text = "🎉 Received from Mac: ${file.name}"
        Toast.makeText(this, "📥 Received from Mac: ${file.name}", Toast.LENGTH_LONG).show()

        // Display received thumbnail preview if image
        if (mimeType.startsWith("image/") || file.extension.lowercase() in listOf("jpg", "jpeg", "png", "webp")) {
            try {
                val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                binding.ivPreview.setImageBitmap(bitmap)
                binding.ivPreview.visibility = View.VISIBLE
                binding.layoutEmptyState.visibility = View.GONE
                binding.layoutCardBottom.visibility = View.VISIBLE
                binding.tvFileName.text = file.name
            } catch (e: Exception) {
                // Fallback
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (!phoneServer.isAlive()) {
            phoneServer.start()
        }
        discoveryManager.startDiscovery()
        discoveryManager.registerPhoneService(phoneServer.port)
        motionDetector.startListening()
    }

    override fun onPause() {
        super.onPause()
        discoveryManager.stopDiscovery()
        motionDetector.stopListening()
    }

    override fun onDestroy() {
        super.onDestroy()
        phoneServer.stop()
        discoveryManager.unregisterPhoneService()
        mediaPlayer?.release()
        mediaPlayer = null
    }
}
