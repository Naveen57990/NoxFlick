package com.naveen.flik

import android.annotation.SuppressLint
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
import com.naveen.flik.network.FlikTransferClient
import com.naveen.flik.sensors.FlickMotionDetector
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var discoveryManager: NsdDiscoveryManager
    private lateinit var transferClient: FlikTransferClient
    private lateinit var motionDetector: FlickMotionDetector

    private var selectedDevice: DiscoveredMac? = null
    private var selectedUri: Uri? = null
    private var isTransferring = false

    private val photoPickerLauncher = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { onFileSelected(it) }
    }

    private val filePickerLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { onFileSelected(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        discoveryManager = NsdDiscoveryManager(this)
        transferClient = FlikTransferClient(this)

        setupUI()
        setupSensors()
        observeDiscovery()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupUI() {
        binding.btnPhotos.setOnClickListener {
            photoPickerLauncher.launch("image/*")
        }

        binding.btnFiles.setOnClickListener {
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
            if (isTransferring || selectedUri == null) return@setOnTouchListener false

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
            if (selectedUri != null && !isTransferring) {
                performFlik(angle, velocity, aimX)
            } else if (selectedUri == null) {
                runOnUiThread {
                    Toast.makeText(this, "Select a photo or file first!", Toast.LENGTH_SHORT).show()
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

    private fun onFileSelected(uri: Uri) {
        selectedUri = uri
        val name = getFileName(uri)
        binding.tvFileName.text = name

        // Preview thumbnail
        try {
            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri))
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(contentResolver, uri)
            }
            binding.ivPreview.setImageBitmap(bitmap)
            binding.ivPreview.visibility = View.VISIBLE
        } catch (e: Exception) {
            binding.ivPreview.visibility = View.GONE
        }

        binding.layoutEmptyState.visibility = View.GONE
        binding.layoutCardBottom.visibility = View.VISIBLE
        binding.tvStatus.text = "Ready to Nox Flick: $name"
    }

    private fun performFlik(angle: Float, velocity: Float, aimX: Float = 0f) {
        val mac = selectedDevice ?: run {
            Toast.makeText(this, "Searching for nearby Mac...", Toast.LENGTH_SHORT).show()
            return
        }
        val uri = selectedUri ?: return

        isTransferring = true
        binding.tvStatus.text = "🚀 Flicking to ${mac.name}..."

        lifecycleScope.launch {
            val success = transferClient.streamFile(mac, uri, angle, velocity, aimX)
            isTransferring = false
            if (success) {
                binding.tvStatus.text = "🎉 Delivered to ${mac.name}!"
                Toast.makeText(this@MainActivity, "Delivered!", Toast.LENGTH_SHORT).show()
                selectedUri = null
                binding.ivPreview.visibility = View.GONE
                binding.layoutCardBottom.visibility = View.GONE
                binding.layoutEmptyState.visibility = View.VISIBLE
            } else {
                binding.tvStatus.text = "❌ Transfer failed"
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

    override fun onResume() {
        super.onResume()
        discoveryManager.startDiscovery()
        motionDetector.startListening()
    }

    override fun onPause() {
        super.onPause()
        discoveryManager.stopDiscovery()
        motionDetector.stopListening()
    }
}
