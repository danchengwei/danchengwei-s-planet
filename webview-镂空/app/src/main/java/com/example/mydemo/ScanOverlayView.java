package com.example.mydemo;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.util.AttributeSet;
import android.view.View;
import android.view.animation.LinearInterpolator;

import androidx.annotation.Nullable;

/**
 * 取景框内原生绘制：延伸虚线、米字格、白色 L 角标、扫描线与粒子动效。
 * 镂空区域由 H5 通过 {@link #setHoleFromWeb(float, float, float, float)} 同步坐标。
 */
public class ScanOverlayView extends View {

    private final RectF holeRect = new RectF();
    private boolean holeReady;
    private float scanPhase;
    private ValueAnimator animator;
    private final Paint pWhiteStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pDash = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pCyanLine = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pGlow = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pParticle = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path clipPath = new Path();

    public ScanOverlayView(Context context) {
        super(context);
        init();
    }

    public ScanOverlayView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        setLayerType(LAYER_TYPE_SOFTWARE, null);
        pWhiteStroke.setStyle(Paint.Style.STROKE);
        pWhiteStroke.setColor(Color.WHITE);

        pDash.setStyle(Paint.Style.STROKE);
        pDash.setColor(Color.parseColor("#D9FFFFFF"));
        pDash.setPathEffect(new DashPathEffect(new float[]{dp(5), dp(4)}, 0));

        pCyanLine.setStyle(Paint.Style.STROKE);
        pCyanLine.setStrokeWidth(dp(2.2f));
        pCyanLine.setColor(Color.parseColor("#FF66EEFF"));

        pParticle.setStyle(Paint.Style.FILL);

        startAnimator();
    }

    private float dp(float v) {
        return v * getResources().getDisplayMetrics().density;
    }

    private void startAnimator() {
        if (animator != null) {
            animator.cancel();
        }
        animator = ValueAnimator.ofFloat(0f, 1f);
        animator.setDuration(2400);
        animator.setRepeatCount(ValueAnimator.INFINITE);
        animator.setInterpolator(new LinearInterpolator());
        animator.addUpdateListener(a -> {
            scanPhase = (float) a.getAnimatedValue();
            invalidate();
        });
        animator.start();
    }

    /**
     * @param left   WebView 内与 getBoundingClientRect 一致的左坐标
     * @param top    顶坐标
     * @param right  右边界（left + width）
     * @param bottom 底边界（top + height）
     */
    public void setHoleFromWeb(float left, float top, float right, float bottom) {
        holeRect.set(left, top, right, bottom);
        holeReady = holeRect.width() > 8 && holeRect.height() > 8;
        invalidate();
    }

    public RectF getHoleRect() {
        return new RectF(holeRect);
    }

    public boolean hasHole() {
        return holeReady;
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        if (animator != null) {
            animator.cancel();
            animator = null;
        }
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (!holeReady) {
            return;
        }

        float holeL = holeRect.left;
        float holeT = holeRect.top;
        float holeR = holeRect.right;
        float holeB = holeRect.bottom;
        float hw = holeRect.width();
        float hh = holeRect.height();

        float innerW = Math.min(hw * 0.62f, hh * 0.72f);
        float innerH = innerW;
        float innerL = holeL + (hw - innerW) / 2f;
        float innerT = holeT + (hh - innerH) / 2f;
        float innerR = innerL + innerW;
        float innerB = innerT + innerH;

        float cx = (innerL + innerR) / 2f;
        float cy = (innerT + innerB) / 2f;

        float cornerRx = dp(16);
        clipPath.reset();
        clipPath.addRoundRect(holeL, holeT, holeR, holeB, cornerRx, cornerRx, Path.Direction.CW);
        canvas.save();
        canvas.clipPath(clipPath);

        pDash.setStrokeWidth(dp(1.1f));
        float inset = dp(10);
        canvas.drawLine(cx, holeT + inset, cx, holeB - inset, pDash);
        canvas.drawLine(holeL + inset, cy, holeR - inset, cy, pDash);

        canvas.drawRect(innerL, innerT, innerR, innerB, pDash);

        canvas.drawLine(cx, innerT, cx, innerB, pDash);
        canvas.drawLine(innerL, cy, innerR, cy, pDash);
        canvas.drawLine(innerL, innerT, innerR, innerB, pDash);
        canvas.drawLine(innerL, innerB, innerR, innerT, pDash);

        float bracket = dp(16);
        float bw = dp(2.8f);
        pWhiteStroke.setStrokeWidth(bw);
        drawCornerBracket(canvas, innerL, innerT, bracket, true, true);
        drawCornerBracket(canvas, innerR, innerT, bracket, true, false);
        drawCornerBracket(canvas, innerL, innerB, bracket, false, true);
        drawCornerBracket(canvas, innerR, innerB, bracket, false, false);

        float margin = dp(14);
        float scanY = innerT + margin + scanPhase * (innerH - 2 * margin);
        canvas.drawLine(innerL - dp(3), scanY, innerR + dp(3), scanY, pCyanLine);

        Shader shader = new LinearGradient(
                cx, scanY,
                cx, scanY + dp(40),
                new int[]{Color.parseColor("#7722CCFF"), Color.TRANSPARENT},
                new float[]{0f, 1f},
                Shader.TileMode.CLAMP);
        pGlow.setShader(shader);
        canvas.drawRect(innerL - dp(6), scanY, innerR + dp(6), scanY + dp(48), pGlow);

        long now = System.currentTimeMillis();
        for (int i = 0; i < 14; i++) {
            double w = (i * 1.1 + now * 0.0018) % 6.28318;
            float pr = dp(1.8f + (i % 4) * 0.6f);
            float ox = cx + (float) Math.cos(w) * innerW * 0.38f;
            float oy = scanY + dp(10) + (i % 5) * dp(5) + (float) Math.sin(w * 2.1) * dp(5);
            int alpha = (int) (90 + 100 * Math.sin(now * 0.004 + i * 0.7));
            if (alpha > 255) {
                alpha = 255;
            }
            if (alpha < 40) {
                alpha = 40;
            }
            pParticle.setColor(Color.argb(alpha, 120, 230, 255));
            canvas.drawCircle(ox, oy, pr, pParticle);
        }

        canvas.restore();
    }

    private void drawCornerBracket(Canvas c, float x, float y, float len, boolean top, boolean left) {
        if (top && left) {
            c.drawLine(x, y, x + len, y, pWhiteStroke);
            c.drawLine(x, y, x, y + len, pWhiteStroke);
        } else if (top) {
            c.drawLine(x, y, x - len, y, pWhiteStroke);
            c.drawLine(x, y, x, y + len, pWhiteStroke);
        } else if (left) {
            c.drawLine(x, y, x + len, y, pWhiteStroke);
            c.drawLine(x, y, x, y - len, pWhiteStroke);
        } else {
            c.drawLine(x, y, x - len, y, pWhiteStroke);
            c.drawLine(x, y, x, y - len, pWhiteStroke);
        }
    }
}
