import 'package:auto_route/auto_route.dart';

import '../../presentation/pages/home_page.dart';

part 'routes.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, initial: true),
  ];
}

final appRouter = AppRouter();
