_G.pac999 = _G.pac999 or {}
local pac999 = _G.pac999

do
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
    end

    pac999.utility = utility
end

do
    local camera = {}

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
                    angle = angle_offset,
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
    local object = {}
    object.registered = {}
    object.factories = {}

    do
        local META = {}
        META.__index = META

        function META:__tostring()
            return "object" .. "[" .. table.concat(self.ComponentNames, ",") .. "]" .. "[" .. self.Identifier .. "]"
        end

        function META:FireEvent(name, ...)
            if not self.events[name] then return false end

            for _, event in ipairs(self.events[name]) do
                event.callback(self, ...)
            end
        end

        function META:AddEvent(name, callback, sub_id)
            self.events[name] = self.events[name] or {}

            local event = {callback = callback, id = sub_id or #self.events[name]}
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

            for _, event in ipairs(self.events[name]) do
                if event.id == sub_id then
                    return true
                end
            end

            return false
        end

        function META:Remove()
            self:FireEvent("Finish")
        end

        function object.Template(name, required)
            local META = {}
            META.ClassName = name
            META.EVENTS = {}
            META.RequiredComponents = required

            function META:Register()
                object.Register(self)
            end

            return META
        end

        function object.Register(META)
            assert(META.ClassName)

            object.registered[META.ClassName] = META
        end

        local function get_metatables(component_names, metatables, done)
            metatables = metatables or {}
            done = done or {}

            for _, name in ipairs(component_names) do
                local meta = object.registered[name]

                if not meta then
                    error(name .. " is an unknown component")
                end

                if meta.RequiredComponents then
                    get_metatables(meta.RequiredComponents, metatables, done)
                end

                if not done[name] then
                    table.insert(metatables, meta)
                    done[name] = true
                end
            end

            return metatables
        end

        function object.CreateFactory(component_names)
            local mixed_metatable = {
                ComponentNames = {}
            }

            local events = {}

            for key, val in pairs(META) do
                mixed_metatable[key] = val
            end

            for i, meta in ipairs(get_metatables(component_names)) do
                mixed_metatable.ComponentNames[i] = meta.ClassName
                mixed_metatable["has_" .. meta.ClassName] = true

                for name, callback in pairs(meta.EVENTS) do
                    table.insert(events, {
                        name = name,
                        callback = callback,
                        id = "metatable_" .. name
                    })
                end

                for key, val in pairs(meta) do
                    mixed_metatable[key] = val
                end
            end

            mixed_metatable.__index = mixed_metatable

            local ref = 0

            local key = table.concat(component_names, "|")

            object.factories[key] = function()
                local tbl = {events = {}}

                for _, event in ipairs(events) do
                    mixed_metatable.AddEvent(tbl, event.name, event.callback, events.id)
                end

                tbl.Identifier = ref
                ref = ref + 1

                local obj = setmetatable(tbl, mixed_metatable)
                obj:FireEvent("Start")

                return obj
            end

            return object.factories[key]
        end

        function object.Create(metatables)
            return object.CreateFactory(metatables)()
        end
    end

    pac999.object = obj
end

do
    local object = pac999.object

    local scene = {}

    local factory = object.CreateFactory({"node", "transform", "bounding_box", "model"})

    scene.world = factory()

    function scene.AddNode()
        local node = factory()
        scene.world:AddChild(node)
        return node
    end

    hook.Add("RenderScene", "pac_999", function()
        for _, child in ipairs(scene.world:GetAllChildrenAndSelf()) do
            child:FireEvent("Update")
        end
    end)

    hook.Add("PostDrawOpaqueRenderables", "pac_999", function()
        for _, child in ipairs(scene.world:GetAllChildrenAndSelf()) do
            child:FireEvent("Render3D")
        end
    end)

    if me then
        local node = scene.AddNode()
        node:SetPosition(here)
    end

    pac999.scene = scene
end

do -- components
    do -- scene node
        local META = pac999.object.Template("node")

        function META.EVENTS:Start()
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

        function META:AddChild(part)
            part.Parent = self
            table.insert(self.Children, part)
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

        local META = pac999.object.Template("transform")

        function META.EVENTS:Start()
            self.Transform = Matrix()
            self.ScaleTransform = Matrix()
            self.LocalScaleTransform = Matrix()
            self.Matrix = Matrix()
        end

        function META.EVENTS:Finish()
            if not IsValid(self.Entity) then return end

            utility.ObjectFunctionHook("pac999", ent, "CalcAbsolutePosition")
        end

        function META:SetEntity(ent)
            self.Entity = ent

            utility.ObjectFunctionHook("pac999", ent, "CalcAbsolutePosition", function()
                print("abs!")
            end)
        end

        function META:InvalidateMatrix()
            if self.InvalidMatrix then return end

            self.InvalidMatrix = true

            for _, child in ipairs(self:GetAllChildren()) do
                child.InvalidMatrix = true
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

            if self.Parent then
                tr = self.Parent:GetMatrix() * tr
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
            self:InvalidateMatrix()
        end

        local function sort(a, b)
            return a:GetMatrix():GetTranslation():Distance(EyePos()) < b:GetMatrix():GetTranslation():Distance(EyePos())
        end

        function META:GetUpdateList()
            return self:GetAllChildrenAndSelf(sort)
        end

        META:Register()
    end

    do -- bounding box
        local utility = pac999.utility

        local META = pac999.object.Template("bounding_box", {"transform", "node"})

        function META.EVENTS:Update()
            local min, max = self:GetWorldSpaceBoundingBoxChildren()

            debugoverlay.Box(Vector(0,0,0), min, max, 0, Color(255,0,0, 0))
            debugoverlay.Sphere(
                self:GetWorldSpaceCenter(),
                self:GetBoundingRadius(),
                0,
                Color(255,0,0, 0)
            )
        end

        function META:SetBoundingBox(min, max)
            self.Min = min
            self.Max = max
        end

        function META:GetBoundingBox()
            return self.Min or Vector(1,1,1)*-50, self.Max or Vector(1,1,1)*50
        end

        function META:GetWorldSpaceBoundingBox()
            local mins, maxs = self:GetBoundingBox()

            local m = self:GetMatrix() * Matrix()
            local ratio = mins - maxs

            m:Translate(LerpVector(0.5, mins, maxs))

            local scale = -ratio

            local s1 = m:GetScale()*-scale
            local s2 = m:GetScale()*scale

            return
                m:GetTranslation() + s1,
                m:GetTranslation() + s2
        end

        function META:GetWorldSpaceCenter()
            return LerpVector(0.5, self:GetWorldSpaceBoundingBox())
        end

        function META:GetBoundingRadius()
            local min, max = self:GetWorldSpaceBoundingBox()
            return min:Distance(max)/2
        end

        function META:GetWorldSpaceBoundingBoxChildren()
            local all = self:GetAllChildrenAndSelf()
            local root = all[1]

            local min = root:GetMatrix():GetTranslation()
            local max = min*1

            for _, child in ipairs(all) do
                local min2, max2 = child:GetBoundingBox()

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

    do -- model
        local utility = pac999.utility
        local models = pac999.models

        local META = pac999.object.Template("model")

        function META.EVENTS:Start()
            self.Model = ClientsideModel("models/props_junk/TrashDumpster01a.mdl")
            self.Model:SetNoDraw(true)

            self:SetModel("models/props_junk/TrashDumpster01a.mdl")
        end

        function META.EVENTS:Render3D()
            local mdl = self.Model
            --mdl:SetBoneMatrix(0, v:GetMatrix())
            local world = self:GetMatrix()

            local m = world * Matrix()
            mdl:SetRenderOrigin(m:GetTranslation())
            m:SetTranslation(vector_origin)
            mdl:EnableMatrix("RenderMultiply", m)
            mdl:SetupBones()
            mdl:DrawModel()
        end

        function META:SetModel(mdl)
            self.Model:SetModel(mdl)
            if self.has_bounding_box then
                local data = models.GetMeshInfo(self.Model:GetModel())
                self:SetBoundingBox(data.min, data.max)
            end
        end

        function META.EVENTS:Finish()
            if not IsValid(self.Entity) then return end

            utility.ObjectFunctionHook("pac999", ent, "CalcAbsolutePosition")
        end

        function META:SetEntity(ent)
            self.Entity = ent

            utility.ObjectFunctionHook("pac999", ent, "CalcAbsolutePosition", function()
                print("abs!")
            end)
        end

        function META:InvalidateMatrix()
            if self.InvalidMatrix then return end

            self.InvalidMatrix = true

            for _, child in ipairs(self:GetAllChildren()) do
                child.InvalidMatrix = true
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

            if self.Parent then
                tr = self.Parent:GetMatrix() * tr
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
            self:InvalidateMatrix()
        end

        local function sort(a, b)
            return a:GetMatrix():GetTranslation():Distance(EyePos()) < b:GetMatrix():GetTranslation():Distance(EyePos())
        end

        function META:GetUpdateList()
            return self:GetAllChildrenAndSelf(sort)
        end

        META:Register()
    end
end