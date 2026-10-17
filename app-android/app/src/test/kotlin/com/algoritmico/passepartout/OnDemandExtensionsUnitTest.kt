// SPDX-FileCopyrightText: 2026 GhostTunnel contributors
//
// SPDX-License-Identifier: GPL-3.0

package com.algoritmico.passepartout

import com.algoritmico.passepartout.business.extensions.isOnDemandEnabled
import com.algoritmico.passepartout.business.extensions.onDemandModule
import com.algoritmico.passepartout.business.extensions.withOnDemandDisabled
import com.algoritmico.passepartout.business.extensions.withOnDemandEnabled
import io.partout.models.OnDemandModulePolicy
import io.partout.models.OpenVPNModule
import io.partout.models.TaggedModuleOnDemand
import io.partout.models.TaggedModuleOpenVPN
import io.partout.models.TaggedProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OnDemandExtensionsUnitTest {
    @Test
    fun withOnDemandEnabled_addsActiveOnDemandModule() {
        val profile = baseProfile()

        val updated = profile.withOnDemandEnabled(newModuleId = MODULE_ID)

        assertTrue(updated.isOnDemandEnabled)
        assertTrue(MODULE_ID in updated.activeModulesIds)
        val module = updated.onDemandModule()
        assertNotNull(module)
        assertEquals(MODULE_ID, module?.id)
        assertEquals(OnDemandModulePolicy.any, module?.policy)
        assertTrue(module?.withSSIDs?.isEmpty() == true)
        assertTrue(module?.withOtherNetworks?.isEmpty() == true)
    }

    @Test
    fun withOnDemandEnabled_isIdempotent() {
        val profile = baseProfile()
            .withOnDemandEnabled(newModuleId = MODULE_ID)

        val updated = profile.withOnDemandEnabled(newModuleId = OTHER_MODULE_ID)

        assertEquals(profile, updated)
        assertFalse(OTHER_MODULE_ID in updated.activeModulesIds)
    }

    @Test
    fun withOnDemandEnabled_reactivatesExistingInactiveModule() {
        val profile = baseProfile().copy(
            modules = listOf(
                TaggedModuleOpenVPN(openVPNModule()),
                TaggedModuleOnDemand(
                    io.partout.models.OnDemandModule(
                        id = MODULE_ID,
                        policy = OnDemandModulePolicy.including,
                        withSSIDs = emptyMap(),
                        withOtherNetworks = emptySet()
                    )
                )
            )
        )
        assertFalse(profile.isOnDemandEnabled)

        val updated = profile.withOnDemandEnabled(newModuleId = OTHER_MODULE_ID)

        assertTrue(updated.isOnDemandEnabled)
        assertTrue(MODULE_ID in updated.activeModulesIds)
        assertFalse(OTHER_MODULE_ID in updated.activeModulesIds)
        assertEquals(OnDemandModulePolicy.including, updated.onDemandModule()?.policy)
        assertEquals(2, updated.modules.size)
    }

    @Test
    fun withOnDemandDisabled_removesModuleAndActiveId() {
        val profile = baseProfile()
            .withOnDemandEnabled(newModuleId = MODULE_ID)

        val updated = profile.withOnDemandDisabled()

        assertFalse(updated.isOnDemandEnabled)
        assertNull(updated.onDemandModule())
        assertFalse(MODULE_ID in updated.activeModulesIds)
        assertTrue(updated.modules.none { it is TaggedModuleOnDemand })
        // Connection module is untouched
        assertEquals(1, updated.modules.size)
        assertEquals(
            baseProfile().activeModulesIds,
            updated.activeModulesIds
        )
    }

    @Test
    fun withOnDemandDisabled_isIdempotent() {
        val profile = baseProfile()

        assertEquals(profile, profile.withOnDemandDisabled())
    }

    private fun baseProfile() = TaggedProfile(
        activeModulesIds = setOf(OPENVPN_MODULE_ID),
        id = "profile-id",
        modules = listOf(TaggedModuleOpenVPN(openVPNModule())),
        name = "Profile"
    )

    private fun openVPNModule() = OpenVPNModule(
        id = OPENVPN_MODULE_ID
    )

    private companion object {
        const val OPENVPN_MODULE_ID = "openvpn-module-id"
        const val MODULE_ID = "on-demand-module-id"
        const val OTHER_MODULE_ID = "other-module-id"
    }
}
