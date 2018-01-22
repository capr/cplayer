--code editor based on codedit engine.

if not ... then require'codedit_demo'; return end

local codedit = require'codedit'
local glue = require'glue'
local player = require'cplayer'
local ft = require'freetype'
local nw = require'nw'
local lib = ft:new()
local cairo = require'cairo'
--[[
local view = require'codedit_view'
]]

local view = glue.inherit({
	--font metrics
	font_file = 'Fixedsys',
	glyph_size = 16,
	--scrollbox options
	vscroll = 'always',
	hscroll = 'auto',
	vscroll_w = 16, --use default
	hscroll_h = 16, --use default
	scroll_page_size = nil,
	--colors
	colors = {
		background = '#080808',
		selection_background = '#999999',
		selection_text = '#333333',
		cursor = '#ffffff',
		text = '#ffffff',
		tabstop = '#111',
		margin_background = '#000000',
		line_number_text = '#66ffff',
		line_number_background = '#111111',
		line_number_highlighted_text = '#66ffff',
		line_number_highlighted_background = '#222222',
		line_number_separator = '#333333',
		line_highlight = '#222222',
		blame_text = '#444444',
		--lexer styles
		default = '#CCCCCC',
		whitespace = '#000000',
		comment = '#56CC66',
		string = '#FF3333',
		number = '#FF6666',
		keyword = '#FFFF00',
		identifier = '#FFFFFF',
		operator = '#FFFFFF',
		error = '#FF0000',
		preprocessor = '#56CC66',
		constant = '#FF3333',
		variable = '#FFFFFF',
		['function'] = '#FF6699',
		class        = '#FFFF00',
		type         = '#56CC66',
		label        = '#FFFF66',
		regex        = '#FF3333',
	},
	--extras
	eol_markers = true,
	minimap = true,
	smooth_vscroll = false,
	smooth_hscroll = false,
}, codedit.view)

function view:draw_scrollbox(x, y, w, h, cx, cy, cw, ch)
	local scroll_x, scroll_y, clip_x, clip_y, clip_w, clip_h = self.player:scrollbox{
		id = self.editor.id..'_scrollbox',
		x = x,
		y = y,
		w = w,
		h = h,
		cx = cx,
		cy = cy,
		cw = cw,
		ch = ch,
		vscroll = self.vscroll,
		hscroll = self.hscroll,
		vscroll_w = self.vscroll_w,
		hscroll_h = self.hscroll_h,
		page_size = self.scroll_page_size or ch,
		--vscroll_step = self.smooth_vscroll and 1 or self.linesize,
		--hscroll_step = self.smooth_hscroll and 1 or self.charsize,
	}

	--local cr = self.player.cr
	--cr:save()

	--cr:translate(clip_x, clip_y)
	--cr:rectangle(0, 0, clip_w, clip_h)
	--cr:clip()
	--cr:translate(scroll_x, scroll_y)
	--cr:translate(self:margins_width(), 0)

	return scroll_x, scroll_y, clip_x, clip_y, clip_w, clip_h
end

function view:clip(x, y, w, h)
	self.player.cr:reset_clip()
	self.player.cr:rectangle(x, y, w, h)
	self.player.cr:clip()
end

function view:draw_rect(x, y, w, h, color)
	self.player:rect(x, y, w, h, self.colors[color])
end

local cache = {}

function player:clear_glpyh_cache()
	for _,t in pairs(cache) do
		if t.image then
			t.image:free()
			t.bitmap:free(t.library)
		end
	end
	cache = {}
end

function player:load_glyph(s, i, face, glyph_size)
	--local j = (str.next_char(s, i) or #s + 1) - 1
	local charcode = s:byte(i,i) --TODO: utf8 -> utf32
	if charcode == nil then return end

	local t = cache[charcode]
	if not t then

		face:select_charmap(ft.FT_ENCODING_UNICODE)
		local glyph_index = face:char_index(charcode)

		local load_mode = bit.bor(
			ft.FT_LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH,
			--ft.FT_LOAD_NO_BITMAP,
			ft.FT_LOAD_NO_HINTING,
			ft.FT_LOAD_NO_AUTOHINT)

		local render_mode = ft.FT_RENDER_MODE_LIGHT

		face:set_char_size(glyph_size * 64)
		face:load_glyph(glyph_index, load_mode)

		local glyph = face.glyph

		if glyph.format ~= ft.FT_GLYPH_FORMAT_BITMAP then
			glyph:render(render_mode)
		end
		assert(glyph.format == ft.FT_GLYPH_FORMAT_BITMAP)

		t = {}
		t.advance_x = glyph.advance.x

		if glyph.bitmap.width > 0 and glyph.bitmap.rows > 0 then

			local bitmap = glyph.library:new_bitmap()
			glyph.library:convert_bitmap(glyph.bitmap, bitmap, 4)

			local cairo_stride = cairo.stride('a8', bitmap.width)

			assert(bitmap.pixel_mode == ft.FT_PIXEL_MODE_GRAY)
			assert(bitmap.pitch == cairo_stride)

			local image = cairo.image_surface{
				data = bitmap.buffer,
				format = 'g8',
				w = bitmap.width,
				h = bitmap.rows,
				stride = cairo_stride,
			}
			t.image = image
			t.bitmap = bitmap
			t.library = glyph.library
			t.bitmap_left = glyph.bitmap_left
			t.bitmap_top = glyph.bitmap_top
		end
	end
	cache[charcode] = t
	if not t.advance_x then return end
	return t
end

function player:render_glyph(glyph, x, y)
	if not glyph.image then return end
	self.cr:mask(glyph.image, x + glyph.bitmap_left, y - glyph.bitmap_top)
end

function view:load_glyph(s, i)
	return self.player:load_glyph(s, i, self.ft_face, self.glyph_size)
end

function view:render_glyph(s, i, x, y)
	local glyph = self:load_glyph(s, i)
	if not glyph then return end
	self.player:render_glyph(glyph, x, y)
end

function view:char_advance_x(s, i)
	local glyph = self:load_glyph(s, i)
	return glyph and (glyph.advance_x / 64) or 0
end

function view:draw_char(x, y, s, i, color)
	self.player:setcolor(self.colors[color] or self.colors.text)
	self:render_glyph(s, i, x, y)
end

--draw a reverse pilcrow at eol
function view:render_eol_marker(line)
	local x, y = self:char_coords(line, self.buffer:visual_col(line, self.buffer:last_col(line) + 1))
	local x = x + 2.5
	local y = y + self.char_baseline - self.line_h + 3.5
	local cr = self.player.cr
	cr:new_path()
	cr:move_to(x, y)
	cr:rel_line_to(0, self.line_h - 0.5)
	cr:move_to(x + 3, y)
	cr:rel_line_to(0, self.line_h - 0.5)
	cr:move_to(x - 2.5, y)
	cr:line_to(x + 3.5, y)
	self.player:stroke('#ffffff66')
	cr:arc(x + 2.5, y + 3.5, 4, - math.pi / 2 + 0.2, - 3 * math.pi / 2 - 0.2)
	cr:close_path()
	self.player:fill('#ffffff66')
	cr:fill()
end

function view:render_eol_markers()
	if self.eol_markers then
		local line1, line2 = self:visible_lines()
		for line = line1, line2 do
			self:render_eol_marker(line)
		end
	end
end

function view:render_minimap()
	local cr = self.player.cr
	local mmap = glue.inherit({editor = self}, self)
	local self = mmap
	local scale = 1/6
	self.vscroll = 'never'
	self.hscroll = 'never'
	self.x = 0
	self.y = 0
	self.w = (100 - self.vscroll_w - 4) / scale
	self.h = self.h * 1/scale
	cr:save()
		cr:translate(self.editor.x + self.editor.w - 100, self.editor.y)
		cr:scale(scale, scale)
		codedit.render(self)
		cr:restore()
	cr:restore()
end

local view_render = view.render
function view:render()
	view_render(self)
	self.player.cr:identity_matrix()
	self.player.cr:reset_clip()
end

local editor = glue.inherit({view = view}, codedit.editor)

function editor:render()
	local cr = self.player.cr
	for i = 1,1 do

		if self.view.ft_face_file ~= self.view.font_file then
			if self.view.ft_face then
				self.view.ft_face:free()
			end
			self.view.ft_face = lib:new_face(self.view.font_file)
			self.view.ft_face_file = self.view.font_file
		end
		self.player:clear_glpyh_cache()
		local line_h = self.view.ft_face.size.metrics.height / 64
		if line_h > 0 then
			self.view.line_h = line_h
		end
		self.view:font_changed()

		self.view:render()
		self.view:render_eol_markers()
		--cr:restore()
		if self.view.minimap then
			self.view:render_minimap()
		end
	end
end

function editor:setactive(active)
	self.player.active = active and self.id or nil
end

function editor:set_clipboard(s)
	nw:app():setclipboard(s, 'text')
end

function editor:get_clipboard()
	return nw:app():getclipboard'text' or ''
end

function player:code_editor(t)
	local id = assert(t.id, 'id missing')
	local ed = t
	if not t.buffer or not t.buffer.lines then
		t.view = t.view and glue.inherit(t.view, view) or view
		t.cursor = t.cursor and glue.inherit(t.cursor, editor.cursor) or editor.cursor
		ed = editor:new(t)
		ed.cursor.changed.blinking = true
	end
	ed.player = self
	ed.view.player = self
	ed.view.editor = ed

	--make the cursor blink
	if ed.cursor.changed.blinking then
		ed.cursor.start_clock = self.clock
		ed.cursor.changed.blinking = false
	end
	ed.cursor.on = (self.clock - ed.cursor.start_clock) % 1 < 0.5

	ed:input(
		true, --self.focused == ed.id,
		self.active,
		self.key,
		self.char,
		self.ctrl,
		self.shift,
		self.alt,
		self.mousex,
		self.mousey,
		self.lbutton,
		self.rbutton,
		self.wheel_delta,
		self.doubleclicked,
		self.tripleclicked,
		self.quadrupleclicked,
		self.waiting_for_tripleclick)
	ed:render()

	return ed
end
