local TEST = true

if pac999_models then
	hook.Remove("RenderScene", "pac_999")
	hook.Remove("RenderScene", "pac_999_input")
	hook.Remove("PostDrawOpaqueRenderables", "pac_999")

	for k,v in pairs(pac999_models) do
		SafeRemoveEntity(v)
	end
	pac999_models = nil
end

_G.pac999 = _G.pac999 or {}
local pac999 = _G.pac999

do
	local table_remove = table.remove

	local utility = {}

	do
		local hooks = {}

		function utility.ObjectFunctionHook(id, tbl, func_name, callback)
			if callback then
				local old = hooks[id] or tbl[func_name]

				tbl[func_name] = function(...)
					if old then
						old(...)
					end
					callback(...)
				end

				hooks[id] = old

				return old
			else
				if hooks[id] ~= nil then
					tbl[func_name] = hooks[id]
					hooks[id] = nil
				end
			end
		end

		function utility.CreateObjectPool(name)
			return {
				i = 1,
				list = {},
				map = {},
				remove = function(self, obj)
					if not self.map[obj] then
						error("tried to remove non existing object in pool " .. name, 2)
					end

					for i = 1, self.i do
						if obj == self.list[i] then
							table_remove(self.list, i)
							self.map[obj] = nil
							self.i = self.i - 1
							break
						end
					end

					if self.map[obj] then
						error("unable to remove " .. tostring(obj) .. " from pool " .. name)
					end
				end,
				insert = function(self, obj)
					if self.map[obj] then
						error("tried to add existing object to pool " .. name, 2)
					end

					self.list[self.i] = obj
					self.map[obj] = self.i
					self.i = self.i + 1
				end,
				call = function(self, func_name, ...)
					for _, obj in ipairs(self.list) do
						if obj[func_name] then
							obj[func_name](obj, ...)
						end
					end
				end,
			}
		end
	end

	pac999.utility = utility
end

do
	local camera = {}

	function camera.IntersectRayWithOBB(pos, ang, min, max)
		local view = camera.GetViewMatrix()


		debugoverlay.BoxAngles(
			pos,
			min,
			max,
			ang,
			0,
			Color(255,0,0, 0)
		)

		return util.IntersectRayWithOBB(
			view:GetTranslation(),
			view:GetForward() * 32000,
			pos,
			ang,
			min,
			max
		)
	end

	function camera.GetViewRay()
		local mx,my = gui.MousePos()

		if not vgui.CursorVisible() then
			mx = ScrW()/2
			my = ScrH()/2
		end

		return gui.ScreenToVector(mx, my)
	end

	function camera.GetViewMatrix()
		local m = Matrix()

		m:SetAngles(camera.GetViewRay():Angle())
		m:SetTranslation(EyePos())

		return m
	end

	pac999.camera = camera
end

do
	local input = {}

	function input.IsGrabbing()
		return _G.input.IsMouseDown(MOUSE_LEFT)
	end

	local function sort_by_camera_distance(a, b)
		return a.entity.transform:GetMatrix():GetTranslation():Distance(EyePos()) <
			b.entity.transform:GetMatrix():GetTranslation():Distance(EyePos())
	end

	function input.Update()
		local inputs = {}

		for i, v in ipairs(pac999.entity.GetAllComponents("input")) do
			table.insert(inputs, v)
		end

		table.sort(inputs, sort_by_camera_distance)

		for i,v in ipairs(inputs) do
			if v.IgnoreZ then
				table.remove(inputs, i)
				table.insert(inputs, 1, v)
			end
		end

		if input.grabbed then
			local obj = input.grabbed
			if not input.IsGrabbing() then
				obj:SetPointerDown(false)
				input.grabbed = nil
			end

			obj:SetPointerOver(true)

			return
		end

		for _, obj in ipairs(inputs) do
			local hit_pos, normal, fraction = obj:CameraRayIntersect()

			if hit_pos then
				for _, obj2 in ipairs(inputs) do
					if obj2 ~= obj then
						obj2:SetPointerOver(false)
					end
				end

				--obj:FireEvent("MouseOver", hit_pos, normal, fraction)
				obj:SetHitPosition(hit_pos)
				obj:SetHitNormal(normal)
				obj:SetPointerOver(true)
				obj:SetPointerDown(input.IsGrabbing())



				if input.IsGrabbing() then
					input.grabbed = obj
				end

				break
			end
		end
	end

	hook.Add("RenderScene", "pac_999_input", function()
		pac999.input.Update()
	end)

	pac999.input = input
end

do
	local models = {}

	do
		local cache = {}

		function models.GetMeshInfo(mdl)
			if not cache[mdl] then
				local data = util.GetModelMeshes(mdl, 0, 0)

				local angle_offset = Angle()
				local temp = ClientsideModel(mdl)
				temp:DrawModel()
				local m = temp:GetBoneMatrix(0)
				if m then
					angle_offset = m:GetAngles()
				end
				temp:Remove()

				local minx,miny,minz = 0,0,0
				local maxx,maxy,maxz = 0,0,0

				for _, data in ipairs(data) do
					for _, vertex in ipairs(data.triangles) do
						if vertex.pos.x < minx then minx = vertex.pos.x end
						if vertex.pos.y < miny then miny = vertex.pos.y end
						if vertex.pos.z < minz then minz = vertex.pos.z end

						if vertex.pos.x > maxx then maxx = vertex.pos.x end
						if vertex.pos.y > maxy then maxy = vertex.pos.y end
						if vertex.pos.z > maxz then maxz = vertex.pos.z end
					end
				end

				cache[mdl] = {
					data = data,
					min = Vector(minx, miny, minz),
					max = Vector(maxx, maxy, maxz),
					angle_offset = angle_offset,
				}
			end

			return cache[mdl]
		end
	end

	do
		local box_mesh = Mesh()
		mesh.Begin(box_mesh, MATERIAL_QUADS, 6)
			mesh.Quad(
				Vector(-1, -1, -1),
				Vector(-1, 1, -1),
				Vector(-1, 1, 1),
				Vector(-1, -1, 1)
			)
			mesh.Quad(
				Vector(1, -1, -1),
				Vector(-1, -1, -1),
				Vector(-1, -1, 1),
				Vector(1, -1, 1)
			)
			mesh.Quad(
				Vector(1, 1, -1),
				Vector(1, -1, -1),
				Vector(1, -1, 1),
				Vector(1, 1, 1)
			)
			mesh.Quad(
				Vector(-1, 1, -1),
				Vector(1, 1, -1),
				Vector(1, 1, 1),
				Vector(-1, 1, 1)
			)
			mesh.Quad(
				Vector(1, -1, 1),
				Vector(-1, -1, 1),
				Vector(-1, 1, 1),
				Vector(1, 1, 1)
			)
			mesh.Quad(
				Vector(1, 1, -1),
				Vector(-1, 1, -1),
				Vector(-1, -1, -1),
				Vector(1, -1, -1)
			)
		mesh.End()

		function models.GetBoxMesh()
			return box_mesh
		end
	end

	do
		pac999_temp_model = pac999_temp_model or ClientsideModel("error.mdl")
		pac999_temp_model:SetNoDraw(true)
		local temp_model = pac999_temp_model

		function models.DrawModel(path, matrix, material)
			temp_model:SetModel(path)
			render.MaterialOverride(material)

			temp_model:EnableMatrix("RenderMultiply", matrix)
			temp_model:SetupBones()
			temp_model:DrawModel()

			render.MaterialOverride()
		end
	end

	pac999.models = models
end

do
	local utility = pac999.utility

	local entity = {}
	entity.component_templates = {}

	entity.entity_pool = utility.CreateObjectPool("entities")
	entity.component_pools = {}

	function entity.GetAll()
		return entity.entity_pool.list
	end

	function entity.GetAllComponents(name)
		return entity.component_pools[name] and entity.component_pools[name].list or {}
	end

	local function table_remove_value(tbl, val)
		for i, v in ipairs(tbl) do
			if v == val then
				table.remove(tbl, i)
				break
			end
		end
	end

	do
		local META = {}

		function META:__index(key)

			if META[key] ~= nil then
				return META[key]
			end

			if self.ComponentFunctions[key] ~= nil then
				return self.ComponentFunctions[key]
			end

			error("no such key: " .. tostring(key))
		end

		function META:__newindex(key, val)
			error("cannot newindex: entity." .. tostring(key) .. " = " .. tostring(val))
		end

		function META:__tostring()
			local names = {}

			for _, component in ipairs(self.Components) do
				table.insert(names, component.ClassName)
			end

			return "entity" .. "[" .. table.concat(names, ",") .. "]" .. "[" .. self.Identifier .. "]"
		end

		function META:Remove()
			self:FireEvent("Finish")

			for i = #self.Components, 1, -1 do
				self:RemoveComponent(self.Components[i].ClassName)
			end

			assert(#self.Components == 0)

			entity.entity_pool:remove(self)
		end


		function META:BuildAccessibleComponentFunctions()
			self.ComponentFunctions = {}

			local blacklist = {
				Start = true,
				Finish = true,
				Register = true,
			}

			for _, component in ipairs(self.Components) do
				for key, val in pairs(getmetatable(component)) do
					if not blacklist[key] and type(val) == "function" then
						local old = self.ComponentFunctions[key]
						if old then
							self.ComponentFunctions[key] = function(ent, ...)
								old(ent, ...)
								return component[key](component, ...)
							end
						else
							self.ComponentFunctions[key] = function(ent, ...)
								return component[key](component, ...)
							end
						end
					end
				end
			end
		end

		function META:AddComponent(name)
			local meta = assert(entity.component_templates[name])
			local component = setmetatable({entity = self}, meta)

			if component.Start then
				component:Start()
			end

			rawset(self, name, component)
			table.insert(self.Components, component)
			entity.component_pools[meta.ClassName]:insert(component)

			for event_name, callback in pairs(meta.EVENTS) do
				self:AddEvent(event_name, callback, "metatable_" .. name, component)
			end

			self:BuildAccessibleComponentFunctions()

			return component
		end

		function META:RemoveComponent(name)
			local component = assert(self[name])

			if component.Finish then
				component:Finish()
			end

			rawset(self, name, nil)
			table_remove_value(self.Components, component)
			entity.component_pools[component.ClassName]:remove(component)

			for event_name in pairs(entity.component_templates[name].EVENTS) do
				self:RemoveEvent(event_name, "metatable_" .. name)
			end

			self:BuildAccessibleComponentFunctions()
		end

		do
			function META:FireEvent(name, ...)
				if not self.events[name] then return false end

				for _, event in ipairs(self.events[name]) do
					event.callback(event.component or self, ...)
				end
			end

			function META:AddEvent(name, callback, sub_id, component)
				self.events[name] = self.events[name] or {}

				local event = {
					callback = callback,
					id = sub_id or #self.events[name],
					component = component,
				}
				table.insert(self.events[name], event)
				return event.id
			end

			function META:RemoveEvents(name)
				if not self.events[name] then return false end

				table.Clear(self.events[name])

				return true
			end

			function META:RemoveEvent(name, sub_id)
				if not self.events[name] then return false end

				for i, event in ipairs(self.events[name]) do
					if event.id == sub_id then
						table.remove(self.events[name], i)
						return true
					end
				end

				return false
			end
		end

		function entity.ComponentTemplate(name, required)
			local META = {}
			META.ClassName = name
			META.EVENTS = {}
			META.RequiredComponents = required
			META.__index = META

			function META:__tostring()
				return "component[" .. self.ClassName .. "]"
			end

			function META:Register()
				entity.Register(self)
			end

			return META
		end

		function entity.Register(META)
			assert(META.ClassName)

			entity.component_pools[META.ClassName] =
			entity.component_pools[META.ClassName] or utility.CreateObjectPool(META.ClassName)

			entity.component_templates[META.ClassName] = META
		end

		local function get_metatables(component_names, metatables, done)
			metatables = metatables or {}
			done = done or {}

			for _, name in ipairs(component_names) do
				local meta = entity.component_templates[name]

				if not meta then
					error(name .. " is an unknown component")
				end

				if not done[name] then
					table.insert(metatables, meta)
					done[name] = true
				end

				if meta.RequiredComponents then
					get_metatables(meta.RequiredComponents, metatables, done)
				end
			end

			return metatables
		end

		local ref = 0

		function entity.Create(component_names)
			local self = setmetatable({
				Identifier = ref,
				Components = {},
				ComponentFunctions = {},
				events = {},
			}, META)

			ref = ref + 1

			entity.entity_pool:insert(self)

			if component_names then
				for _, name in ipairs(component_names) do
					self:AddComponent(name)
				end
			end

			return self
		end
	end

	if TEST then
		local events = {}

		do
			local META = entity.ComponentTemplate("test")

			function META:Start()
				table.insert(events, "start")
			end

			function META.EVENTS:Update()
				table.insert(events, "update")
			end

			function META:Finish()
				table.insert(events, "finish")
			end

			META:Register()

			local META = entity.ComponentTemplate("test2")
			META:Register()
		end

		do
			assert(#entity.GetAll() == 0)
			local a = entity.Create({"test"})
			assert(#entity.GetAll() == 1)
			a:AddComponent("test2")
			assert(#entity.GetAllComponents("test2") == 1)
			a:RemoveComponent("test2")
			assert(#entity.GetAllComponents("test2") == 0)
			a:Remove()
			assert(#entity.GetAll() == 0)
		end

		do
			events = {}

			local obj = entity.Create({"test"})
			obj:FireEvent("Update")
			obj:FireEvent("Update")
			obj:Remove()

			assert(table.remove(events, 1) == "start")
			assert(table.remove(events, 1) == "update")
			assert(table.remove(events, 1) == "update")
			assert(table.remove(events, 1) == "finish")
		end

		do
			local META = entity.ComponentTemplate("test")

			function META:Start()
				self.FooBar = true
			end

			function META:SetFoo(b)
				self.FooBar = b
			end

			META:Register()

			local META = entity.ComponentTemplate("test2")

			function META:SetFoo(b)
				self.FooBar = b
			end

			META:Register()

			local ent = entity.Create()
			local cmp = ent:AddComponent("test")
			assert(cmp.FooBar == true)
			assert(ent.test.FooBar == true)
			assert(entity.GetAllComponents("test")[1].FooBar == true)

			ent:SetFoo("bar")
			assert(cmp.FooBar == "bar")

			ent:AddComponent("test2")
			ent:SetFoo("noyesthat")

			assert(ent.test.FooBar == "noyesthat")
			assert(ent.test2.FooBar == "noyesthat")

			ent:Remove()
		end

		assert(#entity.GetAll() == 0)
	end

	pac999.entity = entity
end

do -- components
	do -- scene node
		local META = pac999.entity.ComponentTemplate("node")

		function META:Start()
			self.Children = {}
			self.Parent = nil
		end

		function META:GetParent()
			return self.Parent
		end

		function META:GetChildren()
			return self.Children
		end

		local function GetChildrenRecursive(self, out)
			for _, child in ipairs(self.Children) do
				table.insert(out, child)
				GetChildrenRecursive(child, out)
			end
		end

		function META:Finish()
			for _, child in ipairs(self:GetAllChildren()) do
				child:Remove()
			end

			local parent = self:GetParent()
			if not parent then return end


			for i, obj in ipairs(parent:GetChildren()) do
				if obj == self then
					table.remove(parent.Children, i)
					break
				end
			end
		end

		function META:GetAllChildren()
			local out = {}
			GetChildrenRecursive(self, out)
			return out
		end

		function META:GetParentList()
			local out = {}

			local node = self.Parent

			if not node then return out end

			repeat
				table.insert(out, node)
				node = node.Parent

			until not node

			return out
		end

		function META:AddChild(ent)
			assert(ent.node)
			ent.node.Parent = self
			table.insert(self.Children, ent.node)
		end

		function META:GetAllChildrenAndSelf(sort_callback)
			local out = {self}

			for i,v in ipairs(self:GetAllChildren()) do
				out[i+1] = v
			end

			if sort_callback then
				sort_callback(out)
			end

			return out
		end

		META:Register()
	end

	do -- transform
		local utility = pac999.utility

		local META = pac999.entity.ComponentTemplate("transform")

		function META:Start()
			self.Transform = Matrix()
			self.ScaleTransform = Matrix()
			self.LocalScaleTransform = Matrix()
			self.Matrix = Matrix()
		end

		function META:Finish()
			if not IsValid(self.Entity) then return end

			--utility.ObjectFunctionHook("pac999", ent, "CalcAbsolutePosition")
		end

		function META:SetEntity(ent)
			self.Entity = ent

			--utility.ObjectFunctionHook("pac999", ent, "CalcAbsolutePosition", function() end)
		end

		function META:InvalidateMatrix()
			if self.InvalidMatrix then return end

			self.InvalidMatrix = true

			for _, child in ipairs(self.entity.node:GetAllChildren()) do
				child.entity.transform.InvalidMatrix = true
			end
		end

		function META:GetMatrix()
			if self.InvalidMatrix then
				self.Matrix = self:BuildMatrix()
				self.InvalidMatrix = false
			end

			return self.Matrix
		end

		function META:BuildMatrix()
			local tr = self.ScaleTransform * self.Transform

			if self.Entity then
				tr = self.Entity:GetWorldTransformMatrix() * tr
			end

			if self.entity.node.Parent then
				tr = self.entity.node.Parent.entity.transform:GetMatrix() * tr
			end

			---tr:Translate(LerpVector(0.5, self:OBBMins(), self:OBBMaxs()))

			tr:SetScale(self.LocalScaleTransform:GetScale())

			return tr
		end

		function META:SetWorldMatrix(m)
			local lm = m:GetInverse() * self:GetMatrix()
			self.Transform = self.Transform * lm:GetInverse()
			self:InvalidateMatrix()
		end

		function META:SetPosition(v)
			self.Transform:SetTranslation(v)
			self:InvalidateMatrix()
		end

		function META:GetWorldPosition()
			return self:GetMatrix():GetTranslation()
		end

		function META:GetLocalPosition()
			return self.Transform:GetTranslation()
		end

		function META:SetAngles(a)
			self.Transform:SetAngles(a)
			self:InvalidateMatrix()
		end

		function META:SetScale(v)
			self.ScaleTransform:Scale(v)
			self:InvalidateMatrix()
		end

		function META:SetLocalScale(v)
			self.LocalScaleTransform:Scale(v)
			self.LOL = true
			self:InvalidateMatrix()
		end

		local function sort(a, b)
			return a:GetMatrix():GetTranslation():Distance(EyePos()) < b:GetMatrix():GetTranslation():Distance(EyePos())
		end

		function META:GetUpdateList()
			return self.entity.node:GetAllChildrenAndSelf(sort)
		end

		META:Register()
	end

	do -- bounding box
		local utility = pac999.utility

		local META = pac999.entity.ComponentTemplate("bounding_box", {"transform", "node"})

		function META.EVENTS:Update()
			do return end
			local min, max = self:GetWorldSpaceBoundingBoxChildren()
			if not min then return end

			debugoverlay.Box(
				Vector(0,0,0),
				min,
				max,
				0,
				Color(255,0,0, 0)
			)

		end

		META.Min = vector_origin
		META.Max = vector_origin

		function META:SetBoundingBox(min, max, angle_offset)
			self.Min = min
			self.Max = max
			self.angle_offset = angle_offset
		end

		function META:GetBoundingBox()
			return self.Min, self.Max
		end

		-- TODO: rotation doesn't work properly
		function META:GetWorldSpaceBoundingBox()
			local mins, maxs = self:GetBoundingBox()

			local m = self.entity.transform:GetMatrix() * Matrix()
			--m:Translate(LerpVector(0.5, mins, maxs))

			if self.angle_offset and self.angle_offset ~= Angle(0,0,0) then
				mins = mins * 1
				maxs = maxs * 1
				local a = self.angle_offset*1
				a:RotateAroundAxis(Vector(0,1,0), -90)
				mins:Rotate(a)
				maxs:Rotate(a)
			end

			local s = m:GetScale()

			local mmins = Matrix()
			mmins:Translate(mins * s)

			local mmaxs = Matrix()
			mmaxs:Translate(maxs * s)

			mmins = mmins * m
			mmaxs = mmaxs * m


			return mmins:GetTranslation(), mmaxs:GetTranslation()
		end

		function META:GetWorldSpaceCenter()
			return LerpVector(0.5, self:GetWorldSpaceBoundingBox())
		end

		function META:GetBoundingRadius()
			local min, max = self:GetWorldSpaceBoundingBox()
			return min:Distance(max)/2
		end

		function META:GetWorldSpaceBoundingBoxChildren()
			local all = self.entity.node:GetAllChildrenAndSelf()
			local root = all[1]

			local min = root.entity.transform:GetMatrix():GetTranslation()
			local max = min*1

			for _, child in ipairs(all) do
				local min2, max2 = child.entity.bounding_box:GetWorldSpaceBoundingBox()

				min.x = math.min(min.x, min2.x)
				min.y = math.min(min.y, min2.y)
				min.z = math.min(min.z, min2.z)


				max.x = math.max(max.x, max2.x)
				max.y = math.max(max.y, max2.y)
				max.z = math.max(max.z, max2.z)
			end

			return min, max
		end

		META:Register()
	end

	do -- input
		local camera = pac999.camera

		local META = pac999.entity.ComponentTemplate("input", {"transform", "bounding_box"})

		function META:SetIgnoreZ(b)
			self.IgnoreZ = b
		end

		function META:SetPointerOver(b)
			if self.Hovered ~= b then
				self.Hovered = b
				self.entity:FireEvent("Pointer", self.Hovered, self.Grabbed)
			end
		end

		function META:SetPointerDown(b)
			if self.Grabbed ~= b then
				self.Grabbed = b
				self.entity:FireEvent("Pointer", self.Hovered, self.Grabbed)
			end
		end

		function META:SetHitNormal(vec)
			self.HitNormal = vec
		end

		function META:GetHitNormal()
			return self.HitNormal
		end


		function META:SetHitPosition(vec)
			self.HitPosition = vec
		end

		function META:GetHitPosition()
			return self.HitPosition
		end

		function META:CameraRayIntersect()
			if not rawget(self.entity, "bounding_box") then return end

			local m = self.entity.transform:GetMatrix()
			local min, max = self.entity.bounding_box:GetWorldSpaceBoundingBox()

			min = min - m:GetTranslation()
			max = max - m:GetTranslation()

			return camera.IntersectRayWithOBB(
				m:GetTranslation(), m:GetAngles(),
				min, max
			)
		end

		META:Register()
	end

	do -- model
		local utility = pac999.utility
		local models = pac999.models

		local META = pac999.entity.ComponentTemplate("model")

		function META:Start()
			pac999_models = pac999_models or {}
			self.Model = ClientsideModel("error.mdl")
			table.insert(pac999_models, self.Model)
			self.Model:SetNoDraw(true)
			self.model_set = false
		end

		function META:SetIgnoreZ(b)
			self.IgnoreZ = b
		end

		function META:Render3D()
			if not self.model_set then return end
			local mdl = self.Model
			local world = self.entity.transform:GetMatrix()

			if self.entity.input.Hovered then
				render.SetColorModulation(5,5,5)
			else
				render.SetColorModulation(1,1,1)
			end

			local m = world * Matrix()
			mdl:SetRenderOrigin(m:GetTranslation())
			m:SetTranslation(vector_origin)
			mdl:EnableMatrix("RenderMultiply", m)
			mdl:SetupBones()

			if self.IgnoreZ then
				cam.IgnoreZ(true)
			end
			mdl:DrawModel()
			if self.IgnoreZ then
				cam.IgnoreZ(false)
			end
		end

		function META:SetModel(mdl)
			self.Model:SetModel(mdl)
			if self.entity.bounding_box then
				local data = models.GetMeshInfo(self.Model:GetModel())
				self.entity.bounding_box:SetBoundingBox(data.min, data.max, data.angle_offset)
			end
			self.model_set = true
		end

		function META:Finish()
			timer.Simple(0, function()
				self.Model:Remove()
			end)
		end

		META:Register()

		hook.Add("PostDrawOpaqueRenderables", "pac_999", function()
			for _, obj in ipairs(pac999.entity.GetAllComponents("model")) do
				obj:Render3D()
			end
		end)
	end

	do -- gizmo
		local function line_plane_intersection(p, n, lp, ln)
			local d = p:Dot(n)
			local t = d - lp:Dot(n) / ln:Dot(n)
			if t < 0 then return end
			return lp + ln * t
		end

		local META = pac999.entity.ComponentTemplate("gizmo")

		local function create_grab(self, mdl, pos, on_grab)
			local obj = pac999.scene.AddNode(self.entity)
			obj:SetIgnoreZ(true)
			obj:RemoveComponent("gizmo")
			obj:SetModel(mdl)
			obj:SetPosition(self:GetCenter() + pos)

			if on_grab then
				obj:AddEvent("Pointer", function(component, hovered, grabbed)
					if grabbed then
						obj:AddEvent("Update", on_grab(obj), obj)
					else
						obj:RemoveEvent("Update", obj)
					end
				end)
			end

			return obj
		end

		function META:GetCenter()
			return self.entity.bounding_box:GetWorldSpaceCenter() - self.entity:GetMatrix():GetTranslation()
		end

		function META:EnableGizmo(b)

			if b then
				local dist = 75

				self.center_axis = create_grab(self, "models/hunter/misc/sphere025x025.mdl", Vector(0,0,0), function()
					local m = pac999.camera.GetViewMatrix():GetInverse() * self.entity.transform:GetMatrix()

					return function()
						self.entity.transform:SetWorldMatrix(pac999.camera.GetViewMatrix() * m)
					end
				end)

				do
					local disc = "models/hunter/tubes/tube4x4x025d.mdl"

					local function build_callback(axis, fixup_callback)
						return function(component)
							local m = self.entity.transform:GetMatrix() * Matrix()

							local temp = m * Matrix()
							temp:Translate(self:GetCenter())
							local center_pos = temp:GetTranslation()

							return function()
								local plane_pos = util.IntersectRayWithPlane(
									pac999.camera.GetViewMatrix():GetTranslation(),
									pac999.camera.GetViewRay(),
									center_pos,
									m[axis](m)
								)

								if not plane_pos then return end

								local rot = Matrix()
								rot:SetAngles((plane_pos - center_pos):Angle())

								local local_angles = (m:GetInverse() * rot):GetAngles()


								-- TODO: figure out why we need to fixup the local angles

								-- not sure why we have to do this
								-- if not, the entire model inverts when it
								-- reaches 180 deg around the rotation
								fixup_callback(local_angles)

								local m = m * Matrix()
								m:Translate(self:GetCenter())
								m:Rotate(local_angles)
								m:Translate(-self:GetCenter())

								self.entity.transform:SetWorldMatrix(m)
							end
						end
					end

					self.x_axis_angle = create_grab(self, disc, Vector(1,0,0)*dist/2, build_callback("GetRight", function(local_angles)
						local_angles.r = -local_angles.y
					end))
					self.x_axis_angle:SetAngles(Angle(45,180,90))
					self.x_axis_angle:SetLocalScale(Vector(1,1,1)*0.25)

					self.y_axis_angle = create_grab(self, disc, Vector(0,1,0)*dist/2, build_callback("GetUp", function(local_angles)
						local_angles.r = -local_angles.p
						local_angles.y = local_angles.y - 90
					end))
					self.y_axis_angle:SetAngles(Angle(0,-90 - 45,0))
					self.y_axis_angle:SetLocalScale(Vector(1,1,1)*0.25)

					self.z_axis_angle = create_grab(self, disc, Vector(0,0,1)*dist/2, build_callback("GetForward", function(local_angles)
						-- this one is realy weird
						local p = local_angles.p

						if local_angles.y > 0 then
							p = -p + 180
						end

						local_angles.r = -90 + p
						local_angles.p = 180
						local_angles.y = 180
					end))
					self.z_axis_angle:SetAngles(Angle(90 +45,90,90))
					self.z_axis_angle:SetLocalScale(Vector(1,1,1)*0.25)
				end


				do
					local function calc_axis(matrix, forward, right, center_pos, cmp)
						local m = matrix * Matrix()
						local pos = m:GetTranslation()

						local plane_pos = line_plane_intersection(
							vector_origin,
							right,
							pac999.camera.GetViewMatrix():GetTranslation() - pos,
							pac999.camera.GetViewRay()
						)

						if not plane_pos then return end

						m:SetTranslation(pos + forward * (plane_pos - center_pos):Dot(forward))

						self.entity.transform:SetWorldMatrix(m)
					end

					local model = "models/hunter/misc/cone1x1.mdl"

					self.x_axis = create_grab(self, model, Vector(1,0,0)*dist, function(component)
						local m = self.entity.transform:GetMatrix()

						local plane_pos = line_plane_intersection(
							vector_origin,
							m:GetRight(),
							pac999.camera.GetViewMatrix():GetTranslation() - m:GetTranslation(),
							pac999.camera.GetViewRay()
						)

						return function()
							calc_axis(m, m:GetForward(), m:GetRight(), plane_pos, component)
						end
					end)
					self.x_axis:SetAngles(Angle(90,0,0))
					self.x_axis:SetLocalScale(Vector(1,1,1)*0.25)


					self.y_axis = create_grab(self, model, Vector(0,1,0)*dist, function(component)
						local m = self.entity.transform:GetMatrix()

						local plane_pos = line_plane_intersection(
							vector_origin,
							m:GetForward(),
							pac999.camera.GetViewMatrix():GetTranslation() - m:GetTranslation(),
							pac999.camera.GetViewRay()
						)

						return function()
							calc_axis(m, m:GetRight(), m:GetForward(), plane_pos, component)
						end
					end)
					self.y_axis:SetAngles(Angle(0,0,-90))
					self.y_axis:SetLocalScale(Vector(1,1,1)*0.25)

					self.z_axis = create_grab(self, model, Vector(0,0,1)*dist, function(component)
						local m = self.entity.transform:GetMatrix()

						local plane_pos = line_plane_intersection(
							vector_origin,
							m:GetRight(),
							pac999.camera.GetViewMatrix():GetTranslation() - m:GetTranslation(),
							pac999.camera.GetViewRay()
						)

						return function()
							calc_axis(m, m:GetUp(), m:GetRight(), plane_pos, component)
						end
					end)
					self.z_axis:SetAngles(Angle(0,0,0))
					self.z_axis:SetLocalScale(Vector(1,1,1)*0.25)
				end
			else
				if self.center_axis then
					self.center_axis:Remove()
					self.x_axis:Remove()
					self.y_axis:Remove()
					self.z_axis:Remove()

					self.x_axis_angle:Remove()
					self.y_axis_angle:Remove()
					self.z_axis_angle:Remove()
				end
			end
			self.gizmoenabled = b
		end

		function META.EVENTS:Pointer(hovered, grabbed)
			if grabbed then
				self:EnableGizmo(not self.gizmoenabled)
			end
		end

		META:Register()
	end
end

do
	local entity = pac999.entity

	local scene = {}

	local components = {
		"node",
		"transform",
		"bounding_box",
		"input",
		"model",
		"gizmo"
	}

	scene.world = entity.Create(components)

	function scene.AddNode(parent)
		parent = parent or scene.world

		local node = entity.Create(components)
		parent.node:AddChild(node)

		return node
	end

	pac999.scene = scene
end

local me = LocalPlayer()

if me then
	local root = pac999.scene.AddNode()
	root:SetPosition(Vector(1000, -500, 1000))

	for i = 1, 10 do
		local node = pac999.scene.AddNode(root)
		node:SetPosition(Vector(50, 0 ,0))
		node:SetModel("models/props_c17/oildrum001.mdl")
		root = node
	end

	for name, objects in pairs(pac999.entity.GetAll()) do
--		print(name, #objects)
	end

	hook.Add("RenderScene", "pac_999", function()
		for _, obj in ipairs(pac999.entity.GetAll()) do
			obj:FireEvent("Update")
		end
	end)
end
