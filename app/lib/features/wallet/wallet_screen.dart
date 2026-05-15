import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/repositories/wallet_repo.dart';

final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});
  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _onlyDebtors = true;

  @override
  Widget build(BuildContext context) {
    final balances = ref.watch(balancesProvider(_onlyDebtors));
    final totalDebt = balances.maybeWhen(
        data: (l) => l.fold<double>(0, (s, b) => s + b.balance),
        orElse: () => 0.0);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          color: AppColors.greenSoft,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: AppColors.greenPrimary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Deuda activa total',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 11)),
                    ]),
              ),
              Text(_money.format(totalDebt),
                  style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy)),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          const Text('Mostrar', style: TextStyle(color: AppColors.muted)),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Solo con deuda'),
            selected: _onlyDebtors,
            onSelected: (s) => setState(() => _onlyDebtors = s),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Todos'),
            selected: !_onlyDebtors,
            onSelected: (s) => setState(() => _onlyDebtors = !s),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: balances.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) => list.isEmpty
              ? const Center(
                  child: Text('Sin clientes',
                      style: TextStyle(color: AppColors.muted)))
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final b = list[i];
                    final color = b.balance > 0 ? AppColors.danger : AppColors.greenPrimary;
                    return ListTile(
                      title: Text(b.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: Text(_money.format(b.balance),
                          style: TextStyle(
                              color: color,
                              fontFamily: 'DMMono',
                              fontWeight: FontWeight.w800)),
                      onTap: () => context.push('/wallet/${b.clientId}'),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}
