import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Maps the SF Symbol names used in the original iOS app to the closest
/// Flutter [IconData]. Falls back to a neutral circle for unknown names.
IconData sfIcon(String name) => _map[name] ?? CupertinoIcons.circle;

const Map<String, IconData> _map = {
  // Tab bar
  'house.fill': CupertinoIcons.house_fill,
  'chart.bar.xaxis': CupertinoIcons.chart_bar_alt_fill,
  'creditcard.fill': CupertinoIcons.creditcard_fill,
  'clock.fill': CupertinoIcons.clock_fill,
  'person.fill': CupertinoIcons.person_fill,
  'plus': CupertinoIcons.plus,
  'exclamationmark.triangle.fill': CupertinoIcons.exclamationmark_triangle_fill,

  // Categories
  'cart.fill': CupertinoIcons.cart_fill,
  'bag.fill': CupertinoIcons.bag_fill,
  'gamecontroller.fill': CupertinoIcons.game_controller_solid,
  'fork.knife': Icons.restaurant,
  'car.fill': CupertinoIcons.car_fill,
  'bolt.fill': CupertinoIcons.bolt_fill,
  'shield.fill': CupertinoIcons.shield_fill,
  'cross.circle.fill': Icons.local_hospital,
  'apps.iphone': CupertinoIcons.device_phone_portrait,
  'building.fill': Icons.apartment,
  'book.closed.fill': Icons.menu_book,
  'banknote.fill': Icons.payments,
  'laptopcomputer': CupertinoIcons.desktopcomputer,
  'chart.line.uptrend.xyaxis': CupertinoIcons.chart_bar_fill,
  'gift.fill': CupertinoIcons.gift_fill,
  'ellipsis.circle.fill': CupertinoIcons.ellipsis_circle_fill,

  // Account types
  'building.columns.fill': Icons.account_balance,
  'chart.bar.fill': CupertinoIcons.chart_bar_fill,

  // Recurrence
  'clock': CupertinoIcons.clock,
  'calendar.badge.clock': Icons.calendar_month,
  'calendar.badge.plus': Icons.event_available,
  'calendar': CupertinoIcons.calendar,
  'calendar.badge.checkmark': Icons.event_available,

  // Directional / status
  'arrow.up': CupertinoIcons.arrow_up,
  'arrow.down': CupertinoIcons.arrow_down,
  'arrow.left.arrow.right': CupertinoIcons.arrow_right_arrow_left,
  'arrow.up.circle.fill': CupertinoIcons.arrow_up_circle_fill,
  'arrow.down.circle.fill': CupertinoIcons.arrow_down_circle_fill,
  'chevron.left': CupertinoIcons.chevron_left,
  'chevron.right': CupertinoIcons.chevron_right,
  'chevron.down': CupertinoIcons.chevron_down,
  'chevron.up': CupertinoIcons.chevron_up,
  'sun.max.fill': CupertinoIcons.sun_max_fill,
  'tray': CupertinoIcons.tray,
  'repeat': CupertinoIcons.repeat,
  'trash': CupertinoIcons.trash,
  'trash.fill': CupertinoIcons.trash_fill,
  'pencil': CupertinoIcons.pencil,
  'pencil.circle.fill': Icons.edit,
  'plus.circle': CupertinoIcons.plus_circle,
  'plus.circle.fill': CupertinoIcons.plus_circle_fill,
  'xmark': CupertinoIcons.xmark,
  'xmark.circle': CupertinoIcons.xmark_circle,
  'checkmark': CupertinoIcons.checkmark_alt,
  'checkmark.circle.fill': CupertinoIcons.checkmark_alt_circle_fill,
  'camera.fill': CupertinoIcons.camera_fill,
  'doc.on.clipboard': Icons.content_paste,
  'star.fill': CupertinoIcons.star_fill,
  'message.fill': CupertinoIcons.chat_bubble_fill,
  'faceid': CupertinoIcons.person_crop_square, // approx
  'touchid': Icons.fingerprint,
  'lock.fill': CupertinoIcons.lock_fill,
  'lock.shield.fill': Icons.gpp_good,
  'bell.fill': CupertinoIcons.bell_fill,
  'gearshape.fill': CupertinoIcons.gear_alt_fill,
  'paintbrush.fill': Icons.brush,
  'dollarsign.circle.fill': Icons.attach_money,
  'target': Icons.track_changes,
  'flag.fill': CupertinoIcons.flag_fill,
  'chart.pie.fill': CupertinoIcons.chart_pie_fill,
  'square.and.arrow.up': CupertinoIcons.share,
  'trash.circle.fill': Icons.delete,
  'checkmark.seal.fill': Icons.verified,
  'hand.raised.fill': CupertinoIcons.hand_raised_fill,
  'info.circle.fill': CupertinoIcons.info_circle_fill,
  'moon.fill': CupertinoIcons.moon_fill,
  'circle.lefthalf.filled': Icons.contrast,
  'wallet.pass.fill': Icons.account_balance_wallet,
  'plusminus': Icons.exposure,
  'minus': CupertinoIcons.minus,
};
