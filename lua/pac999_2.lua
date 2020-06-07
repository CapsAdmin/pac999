--[[
	TODO:
		maybe not use matrices for everything?
			difficult to cram everything into matrices sometimes, maybe it's
			best to do it at cache time

		fix issues with world to local

		lock mouse to axis?
		center gizmo when scaling? maybe on release?

		figure out a better way to mirror everything
]]

local TEST = true
local DEBUG = true

if pac999_models then
	hook.Remove("RenderScene", "pac_999")
	hook.Remove("RenderScene", "pac_999_input")
	hook.Remove("PostDrawOpaqueRenderables", "pac_999")

	for _,v in pairs(pac999_models) do
		SafeRemoveEntity(v)
	end
	pac999_models = nil
end

_G.pac999 = _G.pac999 or {}
local pac999 = _G.pac999

do
	local META = {}
	META.__index = META

	for key, val in pairs(FindMetaTable("VMatrix")) do
		if key ~= "__index" and key ~= "__tostring" and key ~= "__gc" then
			META[key] = function(self, ...)
				local a,b,c = self.m[key](self.m, ...)
				if a == nil then
					return self
				end
				return a,b,c
			end
		end
	end

	function pac999.Matrix44(pos, ang, scale)
		local m = Matrix()
		if pos then
			m:SetTranslation(pos)
		end
		if ang then
			m:SetAngles(ang)
		end
		if scale then
			m:SetScale(scale)
		end

		return setmetatable({m = m}, META)
	end
end

do
	local table_remove = table.remove

	local utility = {}

	function utility.DivideVector(a,b)
		return Vector(a.x / b.x, a.y / b.y, a.z / b.z)
	end

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
						error("tried to remove non existing object '"..tostring(obj).."'  in pool " .. name, 2)
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

	function utility.TriangleIntersect(rayOrigin, rayDirection, world_matrix, v1,v2,v3)
		local EPSILON = 1 / 1048576

		local rdx, rdy, rdz = rayDirection.x, rayDirection.y, rayDirection.z
		local v1x, v1y, v1z = utility.TransformVectorFast(world_matrix, v1)
		local v2x, v2y, v2z = utility.TransformVectorFast(world_matrix, v2)
		local v3x, v3y, v3z = utility.TransformVectorFast(world_matrix, v3)


		-- find vectors for two edges sharing vert0
		--local edge1 = self.y - self.x
		--local edge2 = self.z - self.x
		local e1x, e1y, e1z = (v2x - v1x), (v2y - v1y), (v2z - v1z)
		local e2x, e2y, e2z = (v3x - v1x), (v3y - v1y), (v3z - v1z)

		-- begin calculating determinant - also used to calculate U parameter
		--local pvec = rayDirection:cross( edge2 )
		local pvx = (rdy * e2z) - (rdz * e2y)
		local pvy = (rdz * e2x) - (rdx * e2z)
		local pvz = (rdx * e2y) - (rdy * e2x)

		-- if determinant is near zero, ray lies in plane of triangle
		--local det = edge1:dot( pvec )
		local det = (e1x * pvx) + (e1y * pvy) + (e1z * pvz)

		if (det > -EPSILON) and (det < EPSILON) then return end

		local inv_det = 1 / det

		-- calculate distance from vertex 0 to ray origin
		--local tvec = rayOrigin - self.x
		local tvx = rayOrigin.x - v1x
		local tvy = rayOrigin.y - v1y
		local tvz = rayOrigin.z - v1z

		-- calculate U parameter and test bounds
		--local u = tvec:dot( pvec ) * inv_det
		local u = ((tvx * pvx) + (tvy * pvy) + (tvz * pvz)) * inv_det
		if (u < 0) or (u > 1) then return end

		-- prepare to test V parameter
		--local qvec = tvec:cross( edge1 )
		local qvx = (tvy * e1z) - (tvz * e1y)
		local qvy = (tvz * e1x) - (tvx * e1z)
		local qvz = (tvx * e1y) - (tvy * e1x)

		-- calculate V parameter and test bounds
		--local v = rayDirection:dot( qvec ) * inv_det
		local v = ((rdx * qvx) + (rdy * qvy) + (rdz * qvz)) * inv_det
		if (v < 0) or (u + v > 1) then return end

		-- calculate t, ray intersects triangle
		--local hitDistance = edge2:dot( qvec ) * inv_det
		local hitDistance = ((e2x * qvx) + (e2y * qvy) + (e2z * qvz)) * inv_det

		-- only allow intersections in the forward ray direction
		local dist = (hitDistance >= 0) and hitDistance or nil

		if dist and DEBUG then
			debugoverlay.Triangle(Vector(v1x, v1y, v1z), Vector(v3x, v3y, v3z), Vector(v3x, v3y, v3z), 0, Color(0,255,0,50), true)
			debugoverlay.Triangle(Vector(v3x, v3y, v3z), Vector(v2x, v2y, v2z), Vector(v1x, v1y, v1z), 0, Color(0,255,0,50), true)
		end

		return dist
	end

	function utility.TransformVectorFast(matrix, vec)
		local
		m00,m10,m20,m30,
		m01,m11,m21,m31,
		m02,m12,m22,m32,
		m03,m13,m23,m33
		= matrix:Unpack()

		local x, y, z = vec:Unpack()

		m30 = m00 * x + m10 * y + m20 * z + m30
		m31 = m01 * x + m11 * y + m21 * z + m31
		m32 = m02 * x + m12 * y + m22 * z + m32
		m33 = m03 * x + m13 * y + m23 * z + m33

		return m30,m31,m32
	end

	function utility.TransformVector(matrix, vec)
		return Vector(utility.TransformVectorFast())
	end

	pac999.utility = utility
end

do
	local camera = {}

	function camera.IntersectRayWithOBB(pos, ang, min, max)
		local view = camera.GetViewMatrix()

		local hit_pos, normal, fraction = util.IntersectRayWithOBB(
			view:GetTranslation(),
			view:GetForward() * 32000,
			pos,
			ang,
			min,
			max
		)

		if DEBUG then
			debugoverlay.BoxAngles(
				pos,
				min,
				max,
				ang,
				0,
				Color(255,0,0, a and 50 or 0), true
			)
		end

		return hit_pos, normal, fraction
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
		m:SetTranslation(camera.eye_pos)

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
		return a.entity.bounding_box:GetCameraZSort() < b.entity.bounding_box:GetCameraZSort()
	end

	function input.Update()
		local inputs = {}

		for _, v in ipairs(pac999.entity.GetAllComponents("input")) do
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
			obj.entity:FireEvent("PointerHover")

			return
		end

		for _, obj in ipairs(inputs) do
			local hit_pos, normal, fraction = obj:CameraRayIntersect()

			for _, obj2 in ipairs(inputs) do
				if obj2 ~= obj then
					obj2:SetPointerOver(false)
				end
			end
			if hit_pos then

				--obj:FireEvent("MouseOver", hit_pos, normal, fraction)
				obj:SetHitPosition(hit_pos)
				obj:SetHitNormal(normal)
				obj:SetPointerOver(true)
				obj:SetPointerDown(input.IsGrabbing())
				obj.entity:FireEvent("PointerHover")

				if input.IsGrabbing() then
					input.grabbed = obj
				end

				break
			end
		end
	end

	hook.Remove("Think", "pac_999_input")

	hook.Add("RenderScene", "pac_999_input", function(pos, ang, fov)
		pac999.camera.eye_pos = pos
		pac999.camera.eye_ang = ang
		pac999.camera.eye_fov = fov
		cam.PushModelMatrix(Matrix())
		pac999.input.Update()
		cam.PopModelMatrix()
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
					--m = m:GetInverse()

					angle_offset = m:GetAngles()
					angle_offset.r = 0
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

			return self.Name .. "[" .. table.concat(names, ",") .. "]" .. "[" .. self.Identifier .. "]"
		end

		META.Name = "entity"

		function META:SetName(str)
			rawset(self, "Name", str)
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

		function META:HasComponent(name)
			return rawget(self, name) ~= nil
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
				local name = self.entity.Name
				if name == "entity" then
					name = ""
				else
					name = name .. ": "
				end

				return name .. "component[" .. self.ClassName .. "]"
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
			local a = entity.Create({"test"})
			a:AddComponent("test2")
			a:Remove()
			assert(#entity.GetAllComponents("test2") == 0)
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
			self.LocalScale = Vector(1,1,1)
			self.Matrix = Matrix()


			self.Translation = Matrix()
			self.Rotation = Matrix()
			self.Scale = Vector(1,1,1)

			self.TRScale = Vector(1,1,1)
		end

		if DEBUG then
			function META.EVENTS:Update()
				debugoverlay.BoxAngles(
					self.entity:GetWorldPosition(),
					self.entity:GetMin(),
					self.entity:GetMax(),
					self.entity:GetWorldAngles(),
					0,
					Color(0,0,255,1),
					true
				)
			end
		end

		META.CageSizeMin = Vector(0,0,0)
		META.CageSizeMax = Vector(0,0,0)

		function META:LocalToWorldMatrix(pos, ang)
			local lmat = Matrix()
			lmat:SetTranslation(pos)
			lmat:SetAngles(ang)

			return self:GetWorldMatrix() * lmat
		end

		function META:GetParentMatrix()
			local wmat = self:GetMatrix()

			if self.entity.node and self.entity.node:GetParent() then
				wmat = self.entity.node:GetParent().entity.transform:GetMatrix()
			end

			return wmat
		end

		function META:WorldToLocalMatrix(pos, ang)
			local lmat = Matrix()

			if pos then
				lmat:SetTranslation(pos)
			end

			if ang then
				lmat:SetAngles(ang)
			end

			local wmat = self:GetParentMatrix()


			return wmat:GetInverse() * lmat
		end

		function META:LocalToWorld(pos, ang)
			local wmat = self:LocalToWorldMatrix(pos, ang)
			return wmat:GetTranslation(), wmat:GetAngles()
		end

		function META:WorldToLocal(pos, ang)
			local wmat = self:WorldToLocalMatrix(pos, ang)
			return wmat:GetTranslation(), wmat:GetAngles()
		end

		function META:WorldToLocalPosition(pos)
			return self:WorldToLocalMatrix(pos):GetTranslation()
		end

		function META:WorldToLocalAngles(ang)
			return self:WorldToLocalMatrix(nil, ang):GetAngles()
		end

		function META:GetWorldMatrix()
			local m = self.entity.transform:GetMatrix() * self.entity.transform:GetScaleMatrix()
			--m:Translate(-self.entity.transform:GetCageCenter())

			return m
		end

		do
			META.CageMax = Vector(1,1,1)*0
			META.CageMin = Vector(1,1,1)*0

			META.CageScaleMin = Vector(1,1,1)
			META.CageScaleMax = Vector(1,1,1)

			function META:GetCageSizeMin()
				return self.CageSizeMin
			end

			function META:GetCageSizeMax()
				return self.CageSizeMax
			end

			function META:SetCageSizeMin(val)
				self.CageSizeMin = val
			end

			function META:SetCageSizeMax(s)
				self.CageSizeMax = s
				s = s * 1

				local max = self:GetCageMin()

				if max.x ~= 0 then
					s.x = 1 + s.x / max.x/2
				end

				if max.y ~= 0 then
					s.y = 1 + s.y / max.y/2
				end

				if max.z ~= 0 then
					s.z = 1 + s.z / max.z/2
				end

				self:SetCageScaleMax(s)
			end

			function META:SetCageSizeMin(s)
				self.CageSizeMin = s

				s = s * 1

				local min = self:GetCageMin()

				if min.x ~= 0 then
					s.x = 1 - s.x / min.x/2
				end

				if min.y ~= 0 then
					s.y = 1 - s.y / min.y/2
				end

				if min.z ~= 0 then
					s.z = 1 - s.z / min.z/2
				end

				self:SetCageScaleMin(s)
			end

			function META:SetCageScaleMin(val)
				self.CageScaleMin = val
				self:InvalidateScaleMatrix()
			end

			function META:SetCageScaleMax(val)
				self.CageScaleMax = val
				self:InvalidateScaleMatrix()
			end

			function META:SetCageMin(val)
				self.CageMin = val
				self:InvalidateScaleMatrix()
			end

			function META:SetCageMax(val)
				self.CageMax = val
				self:InvalidateScaleMatrix()
			end

			function META:GetCageMin()
				if self.entity.bounding_box then
					return self.entity.bounding_box:GetCorrectedMin()
				end
				return self.CageMin
			end

			function META:GetCageMax()
				if self.entity.bounding_box then
					return self.entity.bounding_box:GetCorrectedMax()
				end
				return self.CageMax
			end

			function META:InvalidateScaleMatrix()
				if self.entity.bounding_box then
					self.entity.bounding_box:Invalidate()
				end

				local tr = Matrix()
				---self.CageScaleMin = Vector(1,1,1)

				do
					local min = self.CageScaleMin
					local max = self.CageScaleMax


					tr:Translate(self:GetCageMax())
					tr:Scale(max)
					tr:Translate(-self:GetCageMax())


					tr:Translate(self:GetCageMin())
					tr:Scale(Vector(
						((max.x + min.x-1)/max.x),
						((max.y + min.y-1)/max.y),
						((max.z + min.z-1)/max.z)
					))
					tr:Translate(-self:GetCageMin())
				end

				self.ScaleMatrix = tr
			end

			META.ScaleMatrix = Matrix()

			function META:GetScaleMatrix()
				return self.ScaleMatrix
			end

			function META:GetCageCenter()
				if self.entity.bounding_box then
					return self.entity.bounding_box:GetCenter()
				end
				return LerpVector(0.5, self:GetCageMin(), self:GetCageMax())
			end

			function META:GetCageMinMax()
				local center = self:GetCageCenter()
				return self:GetCageMin() - center, self:GetCageMax() - center
			end
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
			self._Scale = nil

			for _, child in ipairs(self.entity.node:GetAllChildren()) do
				child.entity.transform._Scale = nil
				child.entity.transform.InvalidMatrix = true
			end
		end

		function META:GetMatrix()
			if self.InvalidMatrix then
				self.Matrix = self:BuildTRMatrix()
				self.InvalidMatrix = false
			end

			if false then
				if DEBUG then
					debugoverlay.Text(self.Matrix:GetTranslation(), tostring(self), 0)
					debugoverlay.Cross(self.Matrix:GetTranslation(), 2, 0, GREEN, true)

					local min, max = self:GetCageMinMax()

					debugoverlay.BoxAngles(
						self.Matrix:GetTranslation(),
						min * self.Matrix:GetScale(),
						max * self.Matrix:GetScale(),
						self.Matrix:GetAngles(),
						0,
						Color(0,255,0,0),
						true
					)
				end
			end

			return self.Matrix
		end

		-- translation
		-- rotation
		-- scale

		--

		function META:SetIgnoreParentScale(b)
			self.IgnoreParentScale = b
		end

		function META:BuildTRMatrix()
			local tr = self.Transform * Matrix()

			if self.TRScale then
				tr:SetTranslation(tr:GetTranslation() * self.TRScale)
			end

			if self.Entity then
				tr = self.Entity:GetWorldTransformMatrix() * tr
			end

			local parent = self.entity.node.Parent

			if parent then
				parent = parent.entity.transform
				if self.IgnoreParentScale then
					local pm = parent:GetMatrix()*Matrix()
					pm:SetScale(Vector(1,1,1))
					tr = pm * tr
					tr:Scale(self.Scale)
				else
					tr = parent:GetMatrix() * tr
					tr:Scale(self.Scale * parent.Scale)
				end
			end


			---tr:Translate(LerpVector(0.5, self:OBBMins(), self:OBBMaxs()))

			tr:Scale(self.LocalScale)

			return tr
		end

		function META:GetScale()
			return self.Scale
		end

		function META:SetTRMatrix(m)
			self.Transform = m * Matrix()
			self:InvalidateMatrix()
		end

		function META:SetWorldMatrix(m)
			local lm = m:GetInverse() * self:GetMatrix()
			self.Transform = self.Transform * lm:GetInverse()
			self:InvalidateMatrix()
		end

		function META:SetWorldPosition(pos)
			self:SetPosition(self:WorldToLocalPosition(pos))
		end

		function META:GetUp()
			return self:GetMatrix():GetUp()
		end

		function META:GetRight()
			return self:GetMatrix():GetRight()
		end

		function META:GetForward()
			return self:GetMatrix():GetForward()
		end

		function META:GetBackward()
			return self:GetMatrix():GetForward() * -1
		end

		function META:GetLeft()
			return self:GetMatrix():GetRight() * -1
		end

		function META:GetDown()
			return self:GetMatrix():GetUp() * -1
		end

		function META:SetWorldAngles(pos)
			self:SetAngles(self:WorldToLocalAngles(pos))
		end

		function META:GetWorldPosition()
			return self:GetMatrix():GetTranslation()
		end

		function META:GetAngles()
			return self.Transform:GetAngles()
		end

		function META:GetWorldAngles()
			local m = self:GetMatrix()*Matrix()
			m:SetScale(Vector(1,1,1))
			return m:GetAngles()
		end

		function META:SetPosition(v)
			self.Transform:SetTranslation(v)
			self:InvalidateMatrix()
		end

		function META:GetPosition()
			return self.Transform:GetTranslation()
		end

		function META:GetLocalPosition()
			return self.Transform:GetTranslation()
		end

		function META:SetAngles(a)
			self.Transform:SetAngles(a)
			self:InvalidateMatrix()
		end

		function META:Rotate(a)
			self.Transform:Rotate(a)
			self:InvalidateMatrix()
		end

		function META:SetScale(v)
			self.Scale = v
			self:InvalidateMatrix()
		end

		function META:SetTRScale(v)
			self.TRScale = v
			self:InvalidateMatrix()
		end

		function META:SetLocalScale(v)
			self.LocalScale = v
			self:InvalidateMatrix()
		end

		META:Register()
	end

	do -- bounding box
		local utility = pac999.utility
		local camera = pac999.camera

		local META = pac999.entity.ComponentTemplate("bounding_box", {"transform", "node"})

		function META:GetCameraZSort()
			local eye = camera.eye_pos

			if not self.zsort or eye ~= camera.last_eye then
				self.zsort = self:NearestPoint(eye):Distance(eye)
				camera.last_eye = eye
			end

			return self.zsort
		end

		do
			function META:Invalidate()
				local min = self.Min * 1
				local max = self.Max * 1

				if self.angle_offset then
					min:Rotate(self.angle_offset)
					max:Rotate(self.angle_offset)
				end

				self.CorrectedMin = Vector(math.min(min.x, max.x), math.min(min.y, max.y), math.min(min.z, max.z))
				self.CorrectedMax = Vector(math.max(min.x, max.x), math.max(min.y, max.y), math.max(min.z, max.z))

				self.Center = LerpVector(0.5, self.CorrectedMin, self.CorrectedMax)

				local x = math.abs(self.CorrectedMin.x) + math.abs(self.CorrectedMax.x)
				local y = math.abs(self.CorrectedMin.y) + math.abs(self.CorrectedMax.y)
				local z = math.abs(self.CorrectedMin.z) + math.abs(self.CorrectedMax.z)

				self.CorrectedMin = -Vector(x,y,z)/2
				self.CorrectedMax = Vector(x,y,z)/2

				self.BoundingRadius = self.CorrectedMin:Distance(self.CorrectedMax)/2
			end


			META.Min = Vector(-1,-1,-1)
			META.Max = Vector(1,1,1)
			META.CorrectedMin = META.Min*1
			META.CorrectedMax = META.Max*1
			META.BoundingRadius = 0
			META.Center = Vector()

			function META:SetMin(vec)
				self.Min = vec
				self:Invalidate()
			end

			function META:SetMax(vec)
				self.Max = vec
				self:Invalidate()
			end

			function META:SetAngleOffset(ang)
				self.angle_offset = ang
				self:Invalidate()
			end

			function META:GetCorrectedMax()
				return self.CorrectedMax
			end

			function META:GetCorrectedMin()
				return self.CorrectedMin
			end

			function META:GetCenter()
				return self.Center
			end

			function META:GetBoundingRadius()
				return self.BoundingRadius
			end

			function META:GetWorldCenter()
				return LerpVector(0.5, self:GetWorldMin(), self:GetWorldMax())
			end
		end

		function META:NearestPoint(point)
			local pos = self.entity:GetWorldPosition()
			local ang = self.entity:GetWorldAngles()
			local min = self:GetMin()
			local max = self:GetMax()

			local dir = pos - point

			local hit_pos, hit_normal, c = util.IntersectRayWithOBB(
				point,
				dir,
				pos,
				ang,
				min,
				max
			)

			if DEBUG then
				debugoverlay.Cross(point, 10,0)

				if hit_pos then
					debugoverlay.Line(point, hit_pos, 0, Color(0,0,255,255))
					debugoverlay.Line(hit_pos, point + dir, 0, Color(0,255,0,10),true)
				else
					debugoverlay.Line(point, point + dir, 0, Color(255,0,0,255),true)
				end
			end

			return hit_pos or point
		end

		function META:GetMin()
			return self.entity.bounding_box:GetWorldMin() - self.entity.transform:GetWorldPosition()
		end

		function META:GetMax()
			return self.entity.bounding_box:GetWorldMax() - self.entity.transform:GetWorldPosition()
		end

		function META:GetWorldMin()
			local min = self:GetCorrectedMin()
			local m = self.entity.transform:GetMatrix()
			local scale = self.entity.transform:GetScaleMatrix()

			local tr = Matrix()
			tr:SetTranslation(((min + self:GetCenter()) * scale:GetScale() + scale:GetTranslation()) * m:GetScale())
			tr = tr * m

			return tr:GetTranslation()
		end

		-- TODO: rotation doesn't work properly
		function META:GetWorldMax()
			local max = self:GetCorrectedMax()
			local m = self.entity.transform:GetMatrix()
			local scale = self.entity.transform:GetScaleMatrix()

			local tr = Matrix()
			tr:SetTranslation(((max + self:GetCenter()) * scale:GetScale() + scale:GetTranslation()) * m:GetScale())
			tr = tr * m

			--print(utility.TransformVector(m, max + scale:GetTranslation() * m:GetScale()), tr:GetTranslation())

			return tr:GetTranslation()
		end

		META:Register()
	end

	do -- input
		local camera = pac999.camera
		local utility = pac999.utility
		local models = pac999.models

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
			local hit_pos, normal, fraction = camera.IntersectRayWithOBB(
				self.entity.transform:GetWorldPosition(),
				self.entity.transform:GetWorldAngles(),
				self.entity.bounding_box:GetMin(),
				self.entity.bounding_box:GetMax()
			)

			if hit_pos then
				if not self.entity.model then
					return hit_pos, normal, fraction
				end

				local mesh = models.GetMeshInfo(self.entity.model.Model:GetModel())

				if not mesh then
					return hit_pos, normal, fraction
				end

				local world_matrix = self.entity:GetWorldMatrix()
				local eye_pos = camera.GetViewMatrix():GetTranslation()
				local ray = camera.GetViewRay()

				if self.entity.bounding_box.angle_offset then
					local tr = world_matrix:GetTranslation()
					world_matrix:SetTranslation(Vector(0,0,0))
					world_matrix:Rotate(self.entity.bounding_box.angle_offset)
					world_matrix:SetTranslation(tr)
				end

				for _, data in ipairs(mesh.data) do
					for i = 1, #data.triangles, 3 do
						local dist = utility.TriangleIntersect(
							eye_pos,
							ray,
							world_matrix,
							data.triangles[i + 2].pos,
							data.triangles[i + 1].pos,
							data.triangles[i + 0].pos
						)

						if dist then
							return hit_pos, normal, fraction
						end
					end
				end
			end
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

		local function blend(color, alpha, brightness)
			local r,g,b = 1,1,1
			local a = 1

			if color then
				r = color.r / 255
				g = color.g / 255
				b = color.b / 255
			end

			if alpha then
				a = alpha
			end

			if brightness then
				r = r * brightness
				g = g * brightness
				b = b * brightness
			end

			return r,g,b,a
		end

		function META:Render3D()
			if not self.model_set then return end
			local mdl = self.Model
			local world = self.entity.transform:GetMatrix()

			local m = world * Matrix()
			--m:Translate(-self.entity.transform:GetCageCenter())
			mdl:SetRenderOrigin(m:GetTranslation())

			m:SetTranslation(vector_origin)
			mdl:EnableMatrix("RenderMultiply", m * self.entity.transform:GetScaleMatrix())
			mdl:SetupBones()

			if self.IgnoreZ then
				cam.IgnoreZ(true)
			end

			local r,g,b,a =  blend(self.Color, self.Alpha, self.Brightness)

			if self.Material then
				render.MaterialOverride(self.Material)
			end

			if self.entity:HasComponent("input") and self.entity.input.Hovered then
				r = r * 4
				g = g * 4
				b = b * 4
			end

			render.SetBlend(a)
			render.SetColorModulation(r,g,b)

			mdl:DrawModel()

			if self.Material then
				render.MaterialOverride()
			end
			if self.IgnoreZ then
				cam.IgnoreZ(false)
			end
		end

		function META:SetMaterial(mat)
			self.Material = mat
		end

		function META:SetColor(val)
			self.Color = val
		end

		function META:SetAlpha(val)
			self.Alpha = val
		end

		function META:SetModel(mdl)
			self.Model:SetModel(mdl)

			local data = models.GetMeshInfo(self.Model:GetModel())

			if self.entity.bounding_box then
				self.entity.bounding_box:SetMin(data.min)
				self.entity.bounding_box:SetMax(data.max)
				self.entity.bounding_box:SetAngleOffset(data.angle_offset)
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
		local utility = pac999.utility

		local white_mat = CreateMaterial("pac999_white_" .. math.random(), "VertexLitGeneric", {

			["$bumpmap"] = "effects/flat_normal",
			--["$halflambert"] = 1,

			["$phong"] = "1",
			["$phongboost"] = "0.01" ,
			["$phongfresnelranges"] = "[2 5 10]",
			["$phongexponent"] = "0.5",


			["$basetexture"] = "color/white",
			--["$model"] = "1",
			["$nocull"] = "1",
			--["$translucent"] = "0",
			--["$vertexcolor"] = "1",
			--["$vertexalpha"] = "1",
		})

		local RED = Color(255, 80, 80)
		local GREEN = Color(80, 255, 80)
		local BLUE = Color(80,80,255)
		local YELLOW = Color(255,255,80)

		local META = pac999.entity.ComponentTemplate("gizmo")

		local function create_grab(self, mdl, pos, on_grab, on_grab2)
			local ent = pac999.scene.AddNode(self.entity)
			ent:SetIgnoreZ(true)
			ent:RemoveComponent("gizmo")
			ent:SetModel(mdl)
			ent:SetPosition( pos)
			ent:SetMaterial(white_mat)
			ent:SetAlpha(1)
			ent:SetIgnoreParentScale(true)

			if on_grab then
				ent:AddEvent("Pointer", function(component, hovered, grabbed)
					if grabbed then
						local cb = on_grab(ent)
						if cb then
							ent:AddEvent("Update", cb, ent)
						end
					else
						ent:RemoveEvent("Update", ent)
					end
					if on_grab2 then
						on_grab2(ent, grabbed)
					end
				end)
			end

			table.insert(self.grab_entities, ent)

			return ent
		end

		function META:Start()
			self.grab_entities = {}
		end

		local dist = 70
		local thickness = 0.5

		function META:SetupViewTranslation()
			local ent = create_grab(
				self,
				"models/XQM/Rails/gumball_1.mdl",
				Vector(0,0,0),
				function()
					local m = pac999.camera.GetViewMatrix():GetInverse() * self.entity.transform:GetMatrix()

					return function()
						self.entity.transform:SetWorldMatrix(pac999.camera.GetViewMatrix() * m)
					end
				end
			)

			ent:SetColor(YELLOW)
			ent:SetLocalScale(Vector(1,1,1)*0.5)
		end

		function META:StartGrab(axis, center)

			self.grab_matrix = self.entity.transform:GetMatrix() * Matrix()
			center = center or self.grab_matrix:GetTranslation()
			self.old_scale = self.grab_matrix:GetScale()
			self.grab_matrix:SetScale(Vector(1,1,1))
			self.grab_transform = self.entity.transform.Transform * Matrix()
			self.grab_translation = self.grab_transform:GetTranslation()


			self.center_pos = util.IntersectRayWithPlane(
				pac999.camera.GetViewMatrix():GetTranslation(),
				pac999.camera.GetViewRay(),
				center,
				self.grab_matrix[axis](self.grab_matrix)
			)

			if not self.center_pos then return end

			return self.grab_matrix, self.center_pos
		end

		function META:GetGrabPlanePosition(axis, center)
			center = center or self.grab_matrix:GetTranslation()

			local plane_pos = util.IntersectRayWithPlane(
				pac999.camera.GetViewMatrix():GetTranslation(),
				pac999.camera.GetViewRay(),
				center,
				self.grab_matrix[axis](self.grab_matrix)
			)

			return plane_pos
		end

		function META:SetWorldMatrix(m, b)
			if self.old_scale then
				--m:SetScale(self.old_scale)
				--self.grab_matrix:SetScale(self.old_scale)
			end

			self.entity.transform:SetTRMatrix(m * self.grab_matrix:GetInverse() * self.grab_transform)

			if self.old_scale then
				--self.grab_matrix:SetScale(Vector(1,1,1))
			end
		end

		function META:SetupTranslation()
			local dist = 8
			local thickness = 1.5
			local model = "models/hunter/misc/cone1x1.mdl"

			local function build_callback(axis, axis2)
				return function(component)
					local m, center_pos = self:StartGrab(axis)

					if not m then return end

					return function()

						local plane_pos = self:GetGrabPlanePosition(axis)

						if not plane_pos then return end

						local m = m * Matrix()
						local dir = m[axis2](m)
						m:SetTranslation(m:GetTranslation() + dir * (plane_pos - center_pos):Dot(dir))

						self:SetWorldMatrix(m)
					end
				end,
				function(ent, grabbed)
					local axis = axis2
					local key = "visual_move_axis_" .. axis
					if self[key] then
						self[key]:Remove()
						self[key] = nil
					end


					if grabbed then
						local visual = pac999.scene.AddNode(self.entity)
						visual:SetIgnoreZ(true)
						visual:RemoveComponent("gizmo")
						visual:RemoveComponent("input")
						visual:SetModel("models/hunter/blocks/cube025x025x025.mdl")
						visual:SetMaterial(white_mat)
						visual:SetColor(color_white)
						visual:SetAlpha(1)
						visual:SetLocalScale(Vector(thickness/25,thickness/25,32000))

						local a

						if axis == "GetRight" then
							a = Angle(0,0,90)
							visual:SetColor(GREEN)
						elseif axis == "GetUp" then
							a = Angle(0,0,0)
							visual:SetColor(BLUE)
						elseif axis == "GetForward" then
							a = Angle(90,0,0)
							visual:SetColor(RED)
						end
						visual:SetAngles(a)

						self[key] = visual
					end

				end
			end

			local function add_grabbable(gizmo_color, axis, axis2, axis3)
				local m = self.entity:GetWorldMatrix()
				local dir = m[axis2](m)*dist
				local wpos = self.entity:GetWorldPosition()

				do
					local ent = create_grab(self, model, vector_origin, build_callback(axis, axis2))
					ent:SetLocalScale(Vector(1,1,1)*0.25)
					ent:SetWorldPosition(self.entity:NearestPoint(wpos + dir) + dir)
					ent:SetAngles(ent:GetPosition():AngleEx(Vector(0,0,1)) + Angle(90,0,0))
					ent:SetColor(gizmo_color)
					ent:SetWorldPosition(ent:GetWorldPosition() + ent:GetUp() * ent:GetBoundingRadius()*2)
				end

				do
					local ent = create_grab(self, model, vector_origin, build_callback(axis, axis2))
					ent:SetLocalScale(Vector(1,1,1)*0.25)
					ent:SetWorldPosition(self.entity:NearestPoint(wpos - dir) - dir)
					local ang =
					ent:SetAngles(ent:GetPosition():AngleEx(Vector(0,0,1)) + Angle(90,0,0))
					ent:SetColor(gizmo_color)
					ent:SetWorldPosition(ent:GetWorldPosition() + ent:GetUp() * ent:GetBoundingRadius()*2.15)
				end

				return ent
			end

			add_grabbable(RED, "GetRight", "GetForward", "GetRight")
			add_grabbable(GREEN, "GetForward", "GetRight", "GetUp")
			add_grabbable(BLUE, "GetRight", "GetUp", "GetForward")
		end

		function META:SetupRotation()
			local disc = "models/hunter/tubes/tube4x4x025d.mdl"
			local dist = dist*0.5/1.25
			local visual_size = 0.28
			local scale = 0.25

			-- TODO: figure out why we need to fixup the local angles

			-- not sure why we have to do this
			-- if not, the entire model inverts when it
			-- reaches 180 deg around the rotation

			local function build_callback(axis, fixup_callback, invert)

				local function local_matrix(m, dir)
					local lrot = Matrix()
					lrot:Rotate(dir:Angle())
					lrot = m:GetInverse() * lrot
					local temp_ang = lrot:GetAngles()
					fixup_callback(temp_ang)
					lrot = Matrix()
					lrot:SetAngles(temp_ang)
					return lrot
				end

				invert = invert or 1
				return function(ent)
					local m, center_pos = self:StartGrab(axis)

					if not m then return end

					local local_start_rotation = local_matrix(m, (center_pos - m:GetTranslation())*invert)

					return function()
						local plane_pos = self:GetGrabPlanePosition(axis)

						if not plane_pos then return end

						local local_drag_rotation = local_matrix(m, (plane_pos - m:GetTranslation())*invert)

						local m = m * Matrix()

						local ang = (local_start_rotation:GetInverse() * local_drag_rotation):GetAngles()

						if input.IsKeyDown(KEY_LSHIFT) then
							if axis == "GetRight" then
								ang.p = math.Round(ang.p / 45) * 45
							end

							if axis == "GetUp" then
								ang.y = math.Round(ang.y / 45) * 45
							end

							if axis == "GetForward" then
								ang.r = math.Round(ang.r / 45) * 45
							end
						end

						local rot = Matrix()
						rot:SetAngles(ang)
						local ang = (m * rot):GetAngles()

						m:SetAngles(ang)

						self:SetWorldMatrix(m)
						-- TODO
						self.entity.transform:SetPosition(self.grab_transform:GetTranslation())

					end
				end
			end

			local function add_grabbable(axis, axis2, gizmo_color, fixup_callback)
				local disc = "models/props_phx/construct/glass/glass_curve360x2.mdl"

				local m = self.entity:GetWorldMatrix()
				local dir = m[axis2](m) * dist
				local wpos = self.entity:GetWorldPosition()

				do
					local ent = create_grab(self, disc, vector_origin, build_callback(axis, fixup_callback, 1))
					--ent:SetWorldPosition(self.entity:NearestPoint(wpos + dir) + dir)

					if axis == "GetRight" then
						ent:SetAngles(Angle(45,180,90))
					elseif axis == "GetUp" then
						ent:SetAngles(Angle(0,90 -45,0))
					elseif axis == "GetForward" then
						ent:SetAngles(Angle(90 +45,90,90))
					end

					ent:SetLocalScale(Vector(1,1,0.0125) * 0.02 * self.entity:GetBoundingRadius())

					ent:SetColor(gizmo_color)
				end
			end

			add_grabbable("GetRight", "GetForward", RED, function(local_angles)
				local_angles.r = -local_angles.y
			end)

			add_grabbable("GetUp", "GetRight", GREEN, function(local_angles)
				local_angles.r = -local_angles.p
				local_angles.y = local_angles.y - 90
			end)

			add_grabbable("GetForward", "GetUp", BLUE, function(local_angles)
				-- this one is realy weird
				local p = local_angles.p

				if local_angles.y > 0 then
					p = -p + 180
				end

				local_angles.r = -90 + p
				local_angles.p = 180
				local_angles.y = 180
			end)
		end

		function META:SetupScale()
			local visual_size = 0.6
			local scale = 0.5

			local model = "models/hunter/blocks/cube025x025x025.mdl"

			local function build_callback(axis, axis2, reverse)
				return function(component)
					local m = self.entity.transform:GetMatrix() * Matrix()
					m:SetScale(Vector(1,1,1))
					local pos = m:GetTranslation()
					local center_pos = util.IntersectRayWithPlane(
						pac999.camera.GetViewMatrix():GetTranslation() - pos,
						pac999.camera.GetViewRay(),
						vector_origin,
						m[axis](m)
					)

					if not center_pos then return end

					local cage_min_start = reverse and self.entity.transform:GetCageSizeMax()*1 or self.entity.transform:GetCageSizeMin()*1

					return function()

						local plane_pos = util.IntersectRayWithPlane(
							pac999.camera.GetViewMatrix():GetTranslation() - pos,
							pac999.camera.GetViewRay(),
							vector_origin,
							m[axis](m)
						)

						if not plane_pos then return end

						local m = m * Matrix()
						local dir
						local reverse = reverse

						if 	axis2 == "GetForward" then
							if reverse then
								dir = Vector(-1,0,0)
							else
								dir = Vector(1,0,0)
							end
						elseif axis2 == "GetRight" then
							if reverse then
								dir = Vector(0,1,0)
							else
								dir = Vector(0,-1,0)
							end
						elseif axis2 == "GetUp" then
							if reverse then
								dir = Vector(0,0,-1)
							else
								dir = Vector(0,0,1)
							end
						end

						local dist = (plane_pos - center_pos):Dot(m[axis2](m))
						if reverse then
							self.entity.transform:SetCageSizeMax(cage_min_start - (dir * dist))
						else
							self.entity.transform:SetCageSizeMin(cage_min_start + (dir * dist))
						end
					end
				end
			end

			local function add_grabbable(dir, gizmo_angle, gizmo_color, axis, axis2)

				local function update(ent, dir)
					local min = self.entity.bounding_box:GetWorldMin()
					local max = self.entity.bounding_box:GetWorldMax()

					local box_pos = self.entity:NearestPoint(self.entity:GetWorldPosition() + dir * 1000)

					if not box_pos then return end

					ent:SetWorldPosition(box_pos)

					ent.transform:GetMatrix()
				end

				local ent = create_grab(self, model, -dir*dist/1.25, build_callback(axis, axis2, true))
				ent:SetLocalScale(Vector(1,1,1)*scale)
				ent:SetColor(gizmo_color)
				ent:AddEvent("Update", function(ent)
					local m = self.entity.transform:GetMatrix()
					if axis2 == "GetRight" then
						update(ent, m[axis2](m))
					else
						update(ent, m[axis2](m)*-1)
					end
				end)

				local ent = create_grab(self, model, dir*dist/1.25, build_callback(axis, axis2))
				ent:SetLocalScale(Vector(1,1,1)*scale)
				ent:SetColor(gizmo_color)

				ent:AddEvent("Update", function(ent)
					local m = self.entity.transform:GetMatrix()

					if axis2 == "GetRight" then
						update(ent, m[axis2](m) * -1)
					else
						update(ent, m[axis2](m))
					end
				end)

				return ent
			end

			add_grabbable(Vector(1,0,0), Angle(90,0,0), RED, "GetRight", "GetForward")
			add_grabbable(Vector(0,1,0), Angle(0,0,-90), GREEN, "GetForward", "GetRight")
			add_grabbable(Vector(0,0,1), Angle(0,0,0), BLUE, "GetRight", "GetUp")
		end

		function META:EnableGizmo(b)

			--self.entity.transform:InvalidateMatrix()

			if b then
				self:SetupViewTranslation()
				self:SetupTranslation()
				self:SetupRotation()
				self:SetupScale()
			else
				for k,v in pairs(self.grab_entities) do
					v:Remove()
				end
				self.grab_entities = {}
			end
			self.gizmoenabled = b

			--self.entity.transform:SetWorldPosition(LocalPlayer():EyePos())
		end

		function META.EVENTS:PointerHover()
			local local_normal = self.entity.input:GetHitNormal()

			if local_normal == Vector(0,0,1) then

			end
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
	local world = pac999.scene.AddNode()
	world:SetName("world")
	world:SetPosition(Vector(-380, -2184, -895))

	if false then
		local ent = pac999.scene.AddNode(world)
		ent:SetModel("models/hunter/blocks/cube025x025x025.mdl")
		ent:SetName("test")
		ent:SetPosition(Vector(100, 1, 1))
		ent:SetCageSizeMin(Vector(100,0,0))
		ent:SetCageSizeMax(Vector(100,0,0))
		ent:SetLocalScale(Vector(1,1,1))
		ent:SetAngles(Angle(45,45,45))
		ent:EnableGizmo(true)
		if false then
		print(pos, ang)
		local ent = pac999.scene.AddNode(ent)
		ent:SetModel("models/hunter/blocks/cube025x025x025.mdl")
		local pos, ang = ent:WorldToLocal(EyePos(), EyeAngles())
		ent:SetPosition(pos)
		ent:SetAngles(ang)
		end
		--ent:SetWorldPosition(EyePos())
		--ent:SetWorldAngles(EyeAngles())
	end

	if false then
		local root = world
		local i = 1
		local n = function(x,y,z)
			local node = pac999.scene.AddNode(root)
			node:SetName(i)
			i = i + 1
			node:SetPosition(Vector(x,y,z))
			node:SetModel("models/props_c17/lampShade001a.mdl")

			return node
		end


		local m = n(80, 80+35.5*0, 10)
		m.transform:SetCageSizeMax(Vector(35.5*4,1,1))
		m.transform:SetCageSizeMin(Vector(35.5*1,1,1))
		m.transform:SetCageSizeMin(Vector(35.5*2,1,1))
		m.transform:SetCageSizeMin(Vector(35.5*4,1,1))

		local m = n(80, 80+38*1, 10)
		m.transform:SetCageSizeMax(Vector(1,1,1))
		m.transform:SetCageSizeMin(Vector(35.5*4,1,1))

		local m = n(80, 80+38*2, 10)
		m.transform:SetCageSizeMax(Vector(35.5*4,1,1))
		m.transform:SetCageSizeMin(Vector(1,1,1))

		for i = 0, 4 do
			local m = n(80 + (i*-35.5), 80+38*3, 10)
			m:SetAlpha(1)
			m:SetCageSizeMax(Vector(0,0,0))

			if i == 4 then
				m:EnableGizmo(true)
			end

			local m = n(80 + (i*35.5), 80+38*3, 10)
			m:SetCageSizeMax(Vector(0,0,0))
			m:SetAlpha(1)
			m:SetAngles(Angle(45,0,0))
			if i == 4 then
				m:SetAngles(Angle(45,45,0))
				m:EnableGizmo(true)
			end
		end

		local m = n(80, 80+38*4 + 250, 10)
		m.transform:SetCageSizeMax(Vector(1,1,1))
		m.transform:SetCageSizeMin(Vector(35.5*4,1,1))
		m.transform:SetAngles(Angle(0,45,0))
		m.gizmo:EnableGizmo(true)

		for i = 1, 1 do
--			root = n(0, 0, 60)
		end
	end

	world:SetTRScale(Vector(1,1,1))
--	world:SetScale(Vector(1,1,1)/3)

	for k,v in pairs(ents.GetAll()) do
		v.LOL = nil
	end

	for _, ent in ipairs(ents.GetAll()) do
		if IsValid(ent:CPPIGetOwner()) and ent:CPPIGetOwner():UniqueID() == "1416729906" and ent:GetModel() and not ent:GetParent():IsValid() and not ent:GetOwner():IsValid() then
			local node = pac999.scene.AddNode(root)
			node:SetModel(ent:GetModel())

			local m = ent:GetWorldTransformMatrix()
			--m:Translate(node.transform:GetCageCenter())
			node.transform:SetWorldMatrix(m)
			node:EnableGizmo(true)
		end
	end

	hook.Add("PreDrawOpaqueRenderables", "pac_999", function()
		for _, obj in ipairs(pac999.entity.GetAll()) do
			obj:FireEvent("Update")
		end

		do return end

		local tr = LocalPlayer():GetEyeTrace()

		if tr.Entity:IsValid() and tr.Entity:GetModel() and not tr.Entity:IsPlayer() and tr.Entity:CPPIGetOwner():UniqueID() == "1416729906" then
			if not tr.Entity.LOL then
				local node = pac999.scene.AddNode(root)
				node:SetModel(tr.Entity:GetModel())

				local m = tr.Entity:GetWorldTransformMatrix()
				--m:Translate(node.transform:GetCageCenter())
				node.transform:SetWorldMatrix(m)
				--node:EnableGizmo(true)
				tr.Entity.LOL = node
			end
		end

	end)
end
