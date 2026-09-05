/*
 * SPDX-License-Identifier: MIT
 */

#include "saturationeffect.h"

#include "core/output.h"
#include "effect/effecthandler.h"
#include "effect/effectwindow.h"
#include "opengl/glshader.h"

#include <KConfigGroup>
#include <KSharedConfig>

#include <algorithm>
#include <cmath>

static void ensureResources()
{
    Q_INIT_RESOURCE(saturation);
}

namespace KWin
{

static float clampSaturation(float value)
{
    return std::clamp(value, 0.0f, 4.0f);
}

SaturationEffect::SaturationEffect()
    : OffscreenEffect()
{
    readConfig();
    loadShader();

    connect(effects, &EffectsHandler::windowAdded, this, &SaturationEffect::slotWindowAdded);
    connect(effects, &EffectsHandler::windowDeleted, this, &SaturationEffect::slotWindowDeleted);

    syncWindows();
    effects->addRepaintFull();
}

SaturationEffect::~SaturationEffect() = default;

bool SaturationEffect::supported()
{
    return effects->isOpenGLCompositing();
}

void SaturationEffect::loadShader()
{
    ensureResources();
    m_shader = ShaderManager::instance()->generateShaderFromFile(
        ShaderTrait::MapTexture | ShaderTrait::Modulate,
        QString(),
        QStringLiteral(":/effects/wlsaturation/shaders/saturation.frag"));
    if (!m_shader) {
        qWarning("wlsaturation: failed to compile saturation shader");
    }
}

void SaturationEffect::readConfig()
{
    KConfigGroup group(KSharedConfig::openConfig(QStringLiteral("kwinrc")), QStringLiteral("Effect-wlsaturation"));
    m_global = clampSaturation(group.readEntry("Saturation", 1.0));
    m_perOutput.clear();

    const QStringList keys = group.keyList();
    for (const QString &key : keys) {
        if (key == QLatin1String("Saturation")) {
            continue;
        }
        bool ok = false;
        const float value = group.readEntry(key, QString()).toFloat(&ok);
        if (ok) {
            m_perOutput.insert(key, clampSaturation(value));
        }
    }
}

float SaturationEffect::amountFor(const EffectWindow *window) const
{
    if (const LogicalOutput *output = window->screen()) {
        const auto it = m_perOutput.constFind(output->name());
        if (it != m_perOutput.cend()) {
            return it.value();
        }
    }
    return m_global;
}

bool SaturationEffect::wantsWindow(const EffectWindow *window) const
{
    if (!m_shader || window->isDesktop()) {
        return false;
    }
    return std::fabs(amountFor(window) - 1.0f) > 0.0005f;
}

void SaturationEffect::applyToWindow(EffectWindow *window)
{
    if (!wantsWindow(window)) {
        if (m_windows.erase(window)) {
            unredirect(window);
        }
        return;
    }

    redirect(window);
    setShader(window, m_shader.get());
    m_windows.insert(window);
}

void SaturationEffect::syncWindows()
{
    for (EffectWindow *window : effects->stackingOrder()) {
        applyToWindow(window);
    }
}

void SaturationEffect::slotWindowAdded(EffectWindow *window)
{
    applyToWindow(window);
}

void SaturationEffect::slotWindowDeleted(EffectWindow *window)
{
    m_windows.erase(window);
}

void SaturationEffect::reconfigure(ReconfigureFlags flags)
{
    Q_UNUSED(flags)
    readConfig();
    syncWindows();
    effects->addRepaintFull();
}

bool SaturationEffect::isActive() const
{
    return !m_windows.empty();
}

int SaturationEffect::requestedEffectChainPosition() const
{
    // Late in the chain, after most appearance effects.
    return 98;
}

void SaturationEffect::apply(EffectWindow *window, int mask, WindowPaintData &data, WindowQuadList &quads)
{
    Q_UNUSED(mask)
    Q_UNUSED(data)
    Q_UNUSED(quads)
    if (!m_shader) {
        return;
    }
    ShaderBinder binder(m_shader.get());
    m_shader->setUniform("saturationAmount", amountFor(window));
}

}

#include "moc_saturationeffect.cpp"
