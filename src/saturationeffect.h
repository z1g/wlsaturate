/*
 * SPDX-License-Identifier: MIT
 *
 * KWin Wayland replacement for cybriq/saturation (X11 RandR CTM).
 * The compositor is DRM master, so userspace cannot program CRTC CTM.
 * This effect applies the same 3x3 saturation matrix as cmsaturation.pl.
 */

#pragma once

#include "effect/offscreeneffect.h"
#include "opengl/glshadermanager.h"

#include <QHash>
#include <unordered_set>

namespace KWin
{

class SaturationEffect : public OffscreenEffect
{
    Q_OBJECT

public:
    explicit SaturationEffect();
    ~SaturationEffect() override;

    void reconfigure(ReconfigureFlags flags) override;
    bool isActive() const override;
    int requestedEffectChainPosition() const override;
    static bool supported();

protected:
    void apply(EffectWindow *window, int mask, WindowPaintData &data, WindowQuadList &quads) override;

private:
    void loadShader();
    void readConfig();
    void syncWindows();
    float amountFor(const EffectWindow *window) const;
    bool wantsWindow(const EffectWindow *window) const;
    void applyToWindow(EffectWindow *window);

    void slotWindowAdded(EffectWindow *window);
    void slotWindowDeleted(EffectWindow *window);

    float m_global = 1.0f;
    QHash<QString, float> m_perOutput;
    std::unordered_set<EffectWindow *> m_windows;
    std::unique_ptr<GLShader> m_shader;
};

}
