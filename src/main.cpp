/*
 * SPDX-License-Identifier: MIT
 */

#include "saturationeffect.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED(SaturationEffect,
                              "metadata.json",
                              return SaturationEffect::supported();)

}

#include "main.moc"
