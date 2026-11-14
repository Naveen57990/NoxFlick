package com.naveen.flik

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.naveen.flik.databinding.ActivityShareBinding
import com.naveen.flik.discovery.DiscoveredMac
import com.naveen.flik.discovery.NsdDiscoveryManager
import com.naveen.flik.network.FlikTransferClient
import com.naveen.flik.sensors.FlickMotionDetector
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class ShareActivity : AppCompatActivity() {

    private lateinit var binding: ActivityShareBinding
    private lateinit var discoveryManager: NsdDiscoveryManager
    private lateinit var transferClient: FlikTransferClient
    private lateinit var motionDetector: FlickMotionDetector

    private var sharedUris = mutableListOf<Uri>()
    private var sharedText: String? = null
    private var selectedDevice: DiscoveredMac? = null
    private var isTransferring = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityShareBinding.inflate(layoutInflater)
        setContentView(binding.root)

        discoveryManager = NsdDiscoveryManager(this)
        transferClient = FlikTransferClient(this)

        handleIncomingIntent(intent)
        setupUI()
        setupSensors()
        observeDiscovery()
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return

        when (intent.action) {
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("text/") == true) {
                    sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                    binding.tvShareTextPreview.text = sharedText
                    binding.tvShareTextPreview.visibility = View.VISIBLE
                    binding.ivSharePreview.visibility = View.GONE
                } else {
                    @Suppress("DEPRECATION")
                    (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let {
                        sharedUris.add(it)
                        loadThumbnail(it)
                    }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let {
                    sharedUris.addAll(it)
                    it.firstOrNull()?.let { firstUri -> loadThumbnail(firstUri) }
                }
            }
        }
    }

    private fun loadThumbnail(uri: Uri) {
        try {
            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri))
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(contentResolver, uri)
            }
            binding.ivSharePreview.setImageBitmap(bitmap)
            binding.ivSharePreview.visibility = View.VISIBLE
            binding.tvShareTextPreview.visibility = View.GONE
        } catch (e: Exception) {
            binding.ivSharePreview.visibility = View.GONE
            binding.tvShareTextPreview.text = "File ready to Nox Flick"
            binding.tvShareTextPreview.visibility = View.VISIBLE
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupUI() {
        var startX = 0f
        var startY = 0f
        var velocityTracker: VelocityTracker? = null

        binding.shareFlickCard.setOnTouchListener { view, event ->
            if (isTransferring) return@setOnTouchListener false

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
                        val rawAngleRad = Math.atan2(currentX.toDouble(), (-currentY.coerceAtMost(-10f)).toDouble())
                        val flickAngleDeg = Math.toDegrees(rawAngleRad).toFloat().coerceIn(-35f, 35f)
                        val aimX = (currentX / 180f).coerceIn(-1.0f, 1.0f)
                        val speedMag = Math.hypot(vx.toDouble(), vy.toDouble()).toFloat()
                        val flickVelocity = (speedMag / 1500f).coerceIn(1.0f, 2.5f)

                        val flyX = currentX * 3.5f
                        view.animate()
                            .translationX(flyX)
                            .translationY(-1800f)
                            .rotation(flickAngleDeg * 1.3f)
                            .alpha(0.0f)
                            .setDuration(220)
                            .withEndAction {
                                performFlik(flickAngleDeg, flickVelocity, aimX)
                            }
                            .start()
                    } else {
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
            if (!isTransferring) {
                performFlik(angle, velocity, aimX)
            }
        }
    }

    private fun observeDiscovery() {
        lifecycleScope.launch {
            discoveryManager.devices.collectLatest { devices ->
                if (devices.isNotEmpty()) {
                    selectedDevice = devices.first()
                    binding.tvShareDevice.text = "${selectedDevice?.name} • Ready"
                } else {
                    selectedDevice = null
                    binding.tvShareDevice.text = "Searching for nearby Mac..."
                }
            }
        }
    }

    private fun performFlik(angle: Float, velocity: Float, aimX: Float = 0f) {
        val mac = selectedDevice ?: run {
            Toast.makeText(this, "Searching for nearby Mac...", Toast.LENGTH_SHORT).show()
            return
        }

        isTransferring = true
        binding.tvShareStatus.text = "🚀 Flicking to ${mac.name}..."

        lifecycleScope.launch {
            if (sharedText != null && sharedUris.isEmpty()) {
                val success = transferClient.sendLink(mac, sharedText!!)
                if (success) {
                    Toast.makeText(this@ShareActivity, "Link delivered to ${mac.name}!", Toast.LENGTH_SHORT).show()
                    finish()
                } else {
                    binding.tvShareStatus.text = "❌ Failed to send link"
                    isTransferring = false
                }
            } else {
                var allSuccess = true
                for (uri in sharedUris) {
                    val success = transferClient.streamFile(mac, uri, angle, velocity, aimX)
                    if (!success) allSuccess = false
                }
                if (allSuccess) {
                    Toast.makeText(this@ShareActivity, "Delivered to ${mac.name}!", Toast.LENGTH_SHORT).show()
                    finish()
                } else {
                    binding.tvShareStatus.text = "❌ Some files failed to send"
                    isTransferring = false
                }
            }
        }
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
