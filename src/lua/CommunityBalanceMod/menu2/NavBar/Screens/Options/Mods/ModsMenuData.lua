local menu =
{
	categoryName = "CBM",
	entryConfig =
	{
		name = "ispEntry",
		class = GUIMenuCategoryDisplayBoxEntry,
		params =
		{
			label = "CBM: ACCESSIBILITY OPTIONS",
		},
	},
	contentsConfig = ModsMenuUtils.CreateBasicModsMenuContents
	{
		layoutName = "CBM_Options",
		contents =
		{
			{
				name = "CBM_info",
				class = GUIMenuText,
				params = {
					text = "Client-side settings to adjust accessibility of CBM"
				},
			},
			{
				name = "alienstructures",
				class = OP_TT_Checkbox,
				params =
				{
					optionPath = "isp_alien_enabled",
					optionType = "bool",
					default = true,
					tooltip = "Disable for slightly better performance when placing structures",
				},
			
				properties =
				{
					{"Label", "Search valid positions for Alien Structures"},
				},
			},
			{
				name = "marinestructures",
				class = OP_TT_Checkbox,
				params =
				{
					optionPath = "isp_marine_enabled_2",
					optionType = "bool",
					default = true,
					tooltip = "Disable for slightly better performance when placing structures",
				},
			
				properties =
				{
					{"Label", "Search valid positions for Marine Structures"},
				},
			},
			{
				name = "marinerotations",
				class = OP_TT_Checkbox,
				params =
				{
					optionPath = "isp_orientation_enabled",
					optionType = "bool",
					default = true,
					tooltip = "Snap to the closed valid rotation up to 29 Degrees",
				},
			
				properties =
				{
					{"Label", "Improved Rotation Placement"},
				},
			},
			{
				name = "shiftkey",
				class = OP_TT_Checkbox,
				params =
				{
					optionPath = "isp_shift_enabled",
					optionType = "bool",
					default = true,
					tooltip = "Also allows you to check the exit of the robo-factory while moving",
				},
			
				properties =
				{
					{"Label", "Shift-Key for rotating Blueprints"},
				},
			},
			{
				name = "dualrailfiringlock",
				class = OP_TT_Checkbox,
				params =
				{
					optionPath = "ExoA_duallock_rail_enabled",
					optionType = "bool",
					default = false,
					tooltip = "Enable to cause firing of the left arm to fire the right arm (updates upon entering an exosuit)",
				},
			
				properties =
				{
					{"Label", "Dual Railgun Firing Sync"},
				},
			},
			{
				name = "dualminifiringlock",
				class = OP_TT_Checkbox,
				params =
				{
					optionPath = "ExoA_duallock_mini_enabled",
					optionType = "bool",
					default = false,
					tooltip = "Enable to cause firing of the left arm to fire the right arm (updates upon entering an exosuit)",
				},
			
				properties =
				{
					{"Label", "Dual Minigun Firing Sync"},
				},
			},
			{
				name = "dualBTfiringlock",
				class = OP_TT_Checkbox,
				params =
				{
					optionPath = "ExoA_duallock_BT_enabled",
					optionType = "bool",
					default = false,
					tooltip = "Enable to cause firing of the left arm to fire the right arm (updates upon entering an exosuit)",
				},
			
				properties =
				{
					{"Label", "Dual Blowtorch Firing Sync"},
				},
			},
			{
				name = "dualPLfiringlock",
				class = OP_TT_Checkbox,
				params =
				{
					optionPath = "ExoA_duallock_PL_enabled",
					optionType = "bool",
					default = false,
					tooltip = "Enable to cause firing of the left arm to fire the right arm (updates upon entering an exosuit)",
				},
			
				properties =
				{
					{"Label", "Dual Plasma Launcher Firing Sync"},
				},
			},
			{
				name = "CBM_fog_info",
				class = GUIMenuText,
				params = {
					text = "Fog-of-war configuration"
				},
			},
			{
				name = "fogofwar_enabled",
				class = OP_TT_Checkbox,
				params =
				{
					optionPath = "fogofwar_enabled",
					optionType = "bool",
					default = true,

					immediateUpdate = function(self)
						GUIMinimap.kFogBlipsEnabled = self:GetValue()
					end,

					tooltip = "Toggles fog-of-war. Entities leaving LOS will remain visible at their last seen position in the minimap. This option requires the server to also have it enable.",
				},
			
				properties =
				{
					{"Label", "Fog-of-war:"},
				},
			},
			{
				name = "fogofwar_fadeout_enabled",
				class = OP_TT_Expandable_Checkbox,
				params =
				{
					optionPath = "fogofwar_fadeout_enabled",
					optionType = "bool",
					default = true,

					immediateUpdate = function(self)
						if MapBlip then MapBlip.kFogFadeoutEnabled = self:GetValue() end
					end,

					tooltip = "Toggle to fade out fog-of-war players blip over time (applies at the end of blips lifespan).",
				},

				properties =
				{
					{"Label", "- Fade-out"},
				},

				postInit =
				{
					function(self)
						self:HookEvent(GetOptionsMenu():GetOptionWidget("fogofwar_enabled"), "OnValueChanged",
							function(self, value)
								self:SetExpanded(value)
							end)

						self:SetExpanded(GetOptionsMenu():GetOptionWidget("fogofwar_enabled"):GetValue())
					end,
				},
			},
			{
			    name = "fogofwar_opacity",
			    class = OP_TT_Expandable_Number,
			    params =
			    {
			        useResetButton = true,
			        optionPath = "fogofwar_opacity",
			        optionType = "float",
			        default = 0.8,

			        minValue = 0.00,
			        maxValue = 1.00,
			        decimalPlaces = 2,

			        immediateUpdate = function(self)
			            if MapBlip then MapBlip.kFogTransparency = self:GetValue() end
			        end,

			        tooltip = "Configure fog-of-war blips opacity.",
			    },

			    properties =
			    {
			        {"Label", "- Opacity"},
			    },

			    postInit =
			    {
			        function(self)
			            self:HookEvent(GetOptionsMenu():GetOptionWidget("fogofwar_enabled"), "OnValueChanged",
			                function(self, value)
			                    self:SetExpanded(value)
			                end)

			            self:SetExpanded(GetOptionsMenu():GetOptionWidget("fogofwar_enabled"):GetValue())
			        end,
			    },
			},
			{
			    name = "fogofwar_grayness",
			    class = OP_TT_Expandable_Number,
			    params =
			    {
			        useResetButton = true,
			        optionPath = "fogofwar_grayness",
			        optionType = "float",
			        default = 0.75,

			        minValue = 0.00,
			        maxValue = 1.00,
			        decimalPlaces = 2,

			        immediateUpdate = function(self)
			            if MapBlip then MapBlip.kFogGrayness = self:GetValue() end
			        end,

			        tooltip = "Configure how strongly fog-of-war blips are desaturated toward gray (0 = original color, 1 = fully gray).",
			    },

			    properties =
			    {
			        {"Label", "- Grayness"},
			    },

			    postInit =
			    {
			        function(self)
			            self:HookEvent(GetOptionsMenu():GetOptionWidget("fogofwar_enabled"), "OnValueChanged",
			                function(self, value)
			                    self:SetExpanded(value)
			                end)

			            self:SetExpanded(GetOptionsMenu():GetOptionWidget("fogofwar_enabled"):GetValue())
			        end,
			    },
			},
		}
	}
}
table.insert(gModsCategories, menu)
