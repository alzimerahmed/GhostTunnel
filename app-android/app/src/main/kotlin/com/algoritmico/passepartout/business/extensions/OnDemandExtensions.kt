// SPDX-FileCopyrightText: 2026 GhostTunnel contributors
//
// SPDX-License-Identifier: GPL-3.0

package com.algoritmico.passepartout.business.extensions

import io.partout.extensions.moduleId
import io.partout.models.OnDemandModule
import io.partout.models.OnDemandModulePolicy
import io.partout.models.TaggedModuleOnDemand
import io.partout.models.TaggedProfile
import java.util.UUID

/**
 * On-demand surface for the Android feature subset (Phase 12).
 *
 * On-demand state lives in the profile as an active [TaggedModuleOnDemand]
 * module. Toggling it edits the profile model; enforcement is applied by the
 * partout core on connect. Note: the Android core currently logs and skips
 * applying on-demand rules (VpnService.Builder does not expose them), so this
 * surface is model-complete while enforcement remains upstream-dependent.
 */
val TaggedProfile.isOnDemandEnabled: Boolean
    get() = onDemandModule() != null

fun TaggedProfile.onDemandModule(): OnDemandModule? {
    return modules.firstOrNull { tagged ->
        tagged is TaggedModuleOnDemand && tagged.moduleId in activeModulesIds
    }?.let {
        (it as TaggedModuleOnDemand).value
    }
}

fun TaggedProfile.withOnDemandEnabled(newModuleId: String = UUID.randomUUID().toString()): TaggedProfile {
    if (isOnDemandEnabled) {
        return this
    }
    // Re-activate an existing (inactive) module before minting a new one.
    val existingId = modules
        .filterIsInstance<TaggedModuleOnDemand>()
        .firstNotNullOfOrNull { it.moduleId }
    if (existingId != null) {
        return copy(
            activeModulesIds = activeModulesIds + existingId
        )
    }
    val module = OnDemandModule(
        id = newModuleId,
        policy = OnDemandModulePolicy.any,
        withSSIDs = emptyMap(),
        withOtherNetworks = emptySet()
    )
    return copy(
        modules = modules + TaggedModuleOnDemand(module),
        activeModulesIds = activeModulesIds + newModuleId
    )
}

fun TaggedProfile.withOnDemandDisabled(): TaggedProfile {
    if (!isOnDemandEnabled) {
        return this
    }
    val removedIds = modules
        .filterIsInstance<TaggedModuleOnDemand>()
        .mapNotNull { it.moduleId }
        .toSet()
    return copy(
        modules = modules.filterNot { it is TaggedModuleOnDemand },
        activeModulesIds = activeModulesIds - removedIds
    )
}
